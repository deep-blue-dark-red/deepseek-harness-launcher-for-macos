export const name = 'task-monitor'
export const inject = ['webServer']

function empty() { return { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } }

function usageOf(u) {
  if (!u) return { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }
  const un = (u.uncachedInputTokens ?? u.inputTokens) || 0
  const cr = u.cacheReadTokens || 0
  const cw = u.cacheWriteTokens || 0
  return { input: un + cr + cw, output: u.outputTokens || 0, cacheRead: cr, cacheWrite: cw }
}

function sendJson(res, obj, status = 200) {
  if (res.headersSent) return
  res.statusCode = status
  res.setHeader('content-type', 'application/json')
  res.end(JSON.stringify(obj))
}

export function apply(ctx) {
  const sessionController = ctx.get('sessionController')
  const sessions = ctx.get('sessions')
  const timer = ctx.get('timer')

  const byId = {}        // sessionId -> { id, cwd, blank, running, phase, objective, blockedReason, title, createdAt }
  const committed = {}   // sessionId -> { input, output, cacheRead, cacheWrite }
  const live = {}        // sessionId -> live delta beyond committed
  const liveStart = {}   // sessionId -> seq threshold below which usage is already in committed

  async function refreshFromList() {
    if (!sessionController) return
    try {
      const res = await sessionController.list({})
      const items = (res && res.items) || []
      for (const s of items) {
        const id = s && s.sessionId
        if (!id) continue
        const hints = s.projections || {}
        const proj = hints.values || {}
        const goal = proj.goal || {}
        const t = byId[id] = byId[id] || { id }
        t.cwd = s.cwd || t.cwd
        t.blank = !!s.blank
        t.running = !!s.running
        if (proj.title) t.title = proj.title
        else if (goal.objective) t.title = goal.objective
        if (goal.phase) t.phase = goal.phase
        if (goal.blockedReason && goal.blockedReason.message) t.blockedReason = goal.blockedReason.message
        if (t.createdAt == null) {
          const so = sessions && sessions.get(id)
          if (so && so.header && so.header.createdAt != null) t.createdAt = so.header.createdAt
          else t.createdAt = s.updatedAt || null
        }
        const base = usageOf(proj.tokenUsage)
        const c = committed[id] = committed[id] || empty()
        c.input = base.input; c.output = base.output; c.cacheRead = base.cacheRead; c.cacheWrite = base.cacheWrite
        const newBase = hints.asOfSeq || 0
        const prevBase = liveStart[id] || 0
        if (newBase > prevBase) { delete live[id]; liveStart[id] = newBase }
        else { liveStart[id] = prevBase }
      }
    } catch (e) {
      console.error('[task-monitor] refresh failed', e)
    }
  }

  function snapshot() {
    const jobs = []
    const totals = { running: 0, done: 0, paused: 0, blocked: 0, halted: 0, input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }
    for (const id of Object.keys(byId)) {
      const t = byId[id]
      if (t.blank && !t.running) continue
      const c = committed[id] || empty()
      const l = live[id] || empty()
      const input = c.input + l.input
      const output = c.output + l.output
      const cacheRead = c.cacheRead + l.cacheRead
      const cacheWrite = c.cacheWrite + l.cacheWrite
      totals.input += input; totals.output += output; totals.cacheRead += cacheRead; totals.cacheWrite += cacheWrite
      let state
      if (t.running) { state = 'running'; totals.running++ }
      else if (t.phase === 'paused') { state = 'paused'; totals.paused++ }
      else if (t.phase === 'blocked') { state = 'blocked'; totals.blocked++ }
      else { state = 'done'; totals.done++ }
      jobs.push({
        id, state, running: !!t.running, phase: t.phase || null,
        title: t.title || 'Untitled task',
        workspace: t.cwd ? String(t.cwd).split('/').pop() : '',
        cwd: t.cwd || null,
        reason: t.blockedReason || null,
        createdAt: t.createdAt || 0,
        input, output, cacheRead, cacheWrite,
      })
    }
    const rank = (s) => s.state === 'running' ? 0 : (s.state === 'paused' || s.state === 'blocked') ? 1 : 2
    jobs.sort((a, b) => {
      if (rank(a) !== rank(b)) return rank(a) - rank(b)
      if (a.createdAt !== b.createdAt) return (b.createdAt || 0) - (a.createdAt || 0)
      return a.title < b.title ? -1 : a.title > b.title ? 1 : 0
    })
    return { totals, jobs }
  }

  // Live set + running state (server-side, no browser, no activation).
  ctx.on('api-session/status', (sessionId, running) => { if (sessionId && byId[sessionId]) byId[sessionId].running = running })
  ctx.on('agent/status', (payload) => {
    const id = payload && payload.agent && payload.agent.id
    if (id) { const t = byId[id] = byId[id] || { id }; t.running = payload.status === 'running' }
  })
  ctx.on('api-session/added', (summary) => {
    const id = summary && summary.sessionId
    if (!id) return
    const t = byId[id] = byId[id] || { id }
    t.cwd = summary.cwd || t.cwd
    t.running = !!summary.running
    t.blank = !!summary.blank
  })
  ctx.on('api-session/removed', (sessionId) => { if (sessionId) { delete byId[sessionId]; delete committed[sessionId]; delete live[sessionId]; delete liveStart[sessionId] } })
  ctx.on('goal/changed', (payload) => {
    const id = payload && payload.agent && payload.agent.id
    if (!id) return
    const t = byId[id] = byId[id] || { id }
    const op = payload.change && payload.change.operation
    const g = payload.change && payload.change.goal
    if (op === 'clear') { t.phase = null; t.blockedReason = null; return }
    if (g) {
      t.phase = g.phase; t.objective = g.objective
      t.blockedReason = (g.blockedReason && g.blockedReason.message) || null
      if (g.objective) t.title = g.objective
    }
  })
  // Usage beyond the committed baseline (streamed + per-message), per session.
  ctx.on('session/event', (session, event) => {
    const id = session && session.id
    if (!id || !event) return
    const seq = event.seq
    if (seq == null) return
    const ls = liveStart[id] || 0
    if (seq <= ls) return
    if (!byId[id]) byId[id] = { id }
    const so = session
    if (byId[id].createdAt == null && so && so.header && so.header.createdAt != null) byId[id].createdAt = so.header.createdAt
    let u = null
    const type = event.type
    if (type === 'assistant/message' && event.data && event.data.usage) u = event.data.usage
    else if (type === 'assistant/chunk' && event.data && event.data.chunk && event.data.chunk.type === 'usage' && event.data.chunk.usage) u = event.data.chunk.usage
    if (!u) return
    const d = usageOf(u)
    const l = live[id] = live[id] || empty()
    l.input += d.input; l.output += d.output; l.cacheRead += d.cacheRead; l.cacheWrite += d.cacheWrite
  })

  refreshFromList()
  if (timer) ctx.effect(() => timer.interval(() => refreshFromList(), 4000))

  // Host-side API for the macOS launcher (additive to the launcher's own
  // reverse-engineered /api calls; no browser is involved).
  ctx.effect(() => ctx.webServer.register({
    kind: 'exact',
    path: '/launcher/monitor/state',
    handler: (req, res) => sendJson(res, snapshot()),
  }))

  ctx.effect(() => ctx.webServer.register({
    kind: 'exact',
    path: '/launcher/monitor/cancel',
    handler: (req, res) => {
      let body = ''
      req.on('data', (c) => { body += c })
      req.on('end', async () => {
        try {
          const parsed = JSON.parse(body || '{}')
          const id = parsed && parsed.sessionId
          if (!id || !sessionController) return sendJson(res, { ok: false, error: 'no sessionId' }, 400)
          await sessionController.cancel({ sessionId: id })
          sendJson(res, { ok: true })
        } catch (e) {
          sendJson(res, { ok: false, error: String(e && e.message || e) }, 500)
        }
      })
    },
  }))
}
