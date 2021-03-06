# TODO:
# - google calendar/ics integration
# - multi-day events
#   - create by click+drag
#   - edit by drag edges
#   - delete by delete text+enter
#   - clever stacking
# - undo
# - refactor and browserify
# - more clever event placement
#   - at least fix the bug with maxY
# - notes in the corner
# - lazy-reify annotations
# - (later) lazy-xhr annotations

doMonthBounce = no

tag = (name, text) ->
  parts = name.split /(?=[.#])/
  tagName = "div"
  classes = []
  id = undefined
  for p in parts
    switch p[0]
      when '#' then id = p.substr 1
      when '.' then classes.push p.substr 1
      else tagName = p
  element = document.createElement tagName
  element.id = id if id?
  element.classList.add c for c in classes
  element.innerText = text if text
  element

makeExpandingArea = (area) ->
  container = document.createElement('div')
  container.className = 'expandingArea'
  pre = container.appendChild(document.createElement('pre'))
  span = pre.appendChild(document.createElement('span'))
  pre.appendChild(document.createElement('br'))
  area.parentNode.insertBefore(container, area)
  container.appendChild(area)
  area.addEventListener 'input', ->
    span.textContent = area.value
  , false
  span.textContent = area.value
  container.className += ' active'
  return container

class ElementWrapper
  setPos: (r) ->
    if r.left? then @$el.style.left = r.left + 'px'
    if r.top? then @$el.style.top = r.top + 'px'
    return
  setSize: (r) ->
    if r.width? then @$el.style.width = r.width + 'px'
    if r.height? then @$el.style.height = r.height + 'px'
    return

  getPos: ->
    left: parseInt getComputedStyle(@$el).left
    top: parseInt getComputedStyle(@$el).top
  getSize: ->
    width: parseInt getComputedStyle(@$el).width
    height: parseInt getComputedStyle(@$el).height

# Layers contain Views.
class Layer extends ElementWrapper
  constructor: (className = '') ->
    super()
    @views = []
    @$el = tag className + '.layer'
  add: (view) ->
    if !view.$el
      view.$el = view.render()
    @views.push view
    view.layer = @
    @$el.appendChild view.$el
    view
  addBegin: (view) ->
    @views.unshift view
    view.layer = @
    @$el.insertBefore view.$el, @$el.firstChild
    view
  addBeforeFirst: (view, cond) ->
    viewToInsertBefore = null
    for v,i in @views
      if cond v
        viewToInsertBefore = v
        break
    view.layer = @
    @$el.insertBefore view.$el, viewToInsertBefore?.$el
    @views.splice i, 0, view
    view
  remove: (view) ->
    @$el.removeChild view.$el
    @views = (v for v in @views when v isnt view)
    return

# A View is a description of an HTML element in terms of a function which
# generates it.
class View extends ElementWrapper
  constructor: (render) ->
    super()
    @render = render if render?
    @handlers = {}
    #@$el = @render()
  refresh: ->
    newEl = @render()
    if newEl isnt @$el
      for e,fs of @handlers
        for f in fs
          newEl.addEventListener e, f
      @$el.parentNode?.replaceChild(newEl, @$el)
      @$el = newEl
  remove: ->
    @layer?.remove @

  on: (ev, fn) ->
    (@handlers[ev] ||= []).push fn
    @$el.addEventListener ev, fn


## NET ##

class NetQueue
  constructor: ->
    @queue = []
    @in_flight = false
    @retries = 0

  enqueue: (fn) ->
    @queue.push fn
    if not @in_flight
      @popQueue()

  popQueue: ->
    if @queue.length
      @in_flight = true
      f = @queue.shift()
      next = (e) =>
        if e
          if e is 'network error'
            @retry f
          else
            alert 'wargh error, you should probs reload'
            console.error e
          return
        @retries = 0
        @success?()
        @popQueue()
      f next
    else
      @in_flight = false

  retry: (f) ->
    time = Math.min 30000, Math.pow(2, @retries)*1000
    time += Math.random()*time*0.5 - time*0.5/2
    time = Math.max 1000, time
    @retries++
    console.log 'retry #'+@retries+' in '+time
    @failure? time
    setTimeout =>
      @queue.unshift f
      @popQueue()
    , time

xhr =
  query: (method, url, data, cb) ->
    req = new XMLHttpRequest
    req.timeout = 5000
    req.onload = ->
      try
        cb null, JSON.parse this.responseText
      catch e
        cb e
    req.onerror = ->
      cb 'network error'
    req.ontimeout = ->
      cb 'network error'
    req.onabort = ->
      cb 'network error'
    req.open method, url, true
    req.setRequestHeader 'Content-Type', 'application/json'
    req.send data
  get: (url, cb) ->
    this.query 'get', url, undefined, cb
  post: (url, data, cb) ->
    this.query 'post', url, JSON.stringify(data), cb
  put: (url, data, cb) ->
    this.query 'put', url, JSON.stringify(data), cb
  delete: (url, cb) ->
    this.query 'delete', url, undefined, cb

class ErrorView extends View
  render: ->
    e = tag '.error', "Error saving data, retrying..."
    e.style.bottom = '-35px'
    e.insertBefore tag('.icon', '!'), e.firstChild
    e
  fadeIn: ->
    @$el.style.bottom = '35px'
  fadeOut: ->
    @$el.style.bottom = '-35px'

errorMessage = new ErrorView

queue = new NetQueue

queue.success = ->
  errorMessage.fadeOut()

queue.failure = ->
  errorMessage.fadeIn()


## GEOMETRY ##

dayForWorldX = (x) ->
  moment(origin).add('days', Math.floor(x/50))

topForDay = (m) ->
  m = moment(m)
  i = m.day()
  v = if 0 < i < 6
    Math.round(15 - Math.sin(i/6 * Math.PI) * 80)
  else 0
  if doMonthBounce
    j = m.date()/m.daysInMonth()
    monthBounce = -Math.sin(j*Math.PI) * 150
    v + monthBounce
  else
    v

leftForDay = (m) ->
  m.diff(origin, 'day')*50

posForDay = (m) ->
  left: leftForDay(m)
  top: topForDay(m)

posForMonth = (m) ->
  left: leftForDay(m)
  top: 40


## VIEWS ##

class DayView extends View
  constructor: (@moment) -> super()
  render: ->
    @isToday = @moment.isSame(moment(), 'day')
    if @$el
      if @isToday
        @$el.classList.add 'today'
      else
        @$el.classList.remove 'today'
      return @$el
    d = tag '.day', @moment.format('ddd')
    num = d.appendChild tag '.number', @moment.format('D')
    if @isToday
      d.classList.add 'today'
    d.addEventListener 'mousedown', (e) =>
      e.preventDefault()
      window.addEventListener 'mousemove', move = (e) =>
        e.preventDefault()
        e.stopPropagation()
        x = e.pageX + sx
        d = dayForWorldX x
        if not d.isSame(@moment, 'day')
          done()
          @beginDrag()
      window.addEventListener 'mouseup', done = (e) =>
        window.removeEventListener 'mousemove', move
        window.removeEventListener 'mouseup', done, true
        window.removeEventListener 'blur', done
        e?.preventDefault()
        e?.stopPropagation()
      , true
      window.addEventListener 'blur', done
    d.addEventListener 'click', =>
      newAnnotation @moment
    d.addEventListener 'touchend', =>
      newAnnotation @moment
    d

  beginDrag: ->
    sa = addSpanningAnnotation
      date: @moment.format('YYYY-MM-DD')
      span: 0
      text: ''
    sa.beginDrag 'right'
    sa._onDragComplete = ->
      delete sa._onDragComplete
      sa.edit()

day = (m) ->
  v = new DayView m
  v.$el = v.render()
  v

month = (m) ->
  v = new View ->
    tag '.month', m.format('MMMM YYYY')
  v.$el = v.render()
  v

class AnnotationView extends View
  constructor: (@data) ->
    super()
  render: ->
    e = tag '.annotation'
    @spacer = e.appendChild tag 'div'
    @spacer.style.width = '0px'
    @content = e.appendChild tag '.content'
    @content.textContent = @data.text
    @content.onclick = =>
      @edit()
    e
  edit: ->
    return if @editing
    @editing = true
    value = @content.textContent
    @content.textContent = ''
    @textArea = @content.appendChild tag 'textarea'
    @textArea.value = value
    @textArea.style.minWidth = '20px'
    makeExpandingArea @textArea
    @textArea.onblur = => @doneEditing()
    @textArea.addEventListener 'input', =>
      @setHeight minHeightForAnnotation @
    @textArea.addEventListener 'keydown', (e) =>
      if e.which is 13 and not e.shiftKey
        e.preventDefault()
        @doneEditing()
    @textArea.focus()
  doneEditing: ->
    return unless @editing
    @editing = false
    value = @data.text = @textArea.value
    if value.length is 0
      @delete()
      @fadeOut()
      return
    else
      @save()
    @content.textContent = value

  setHeight: (height) ->
    @spacer.style.height = height + 'px'

  fadeOut: ->
    @spacer.style.height = '0px'
    @spacer.style.webkitTransition = '200ms ease-in'
    @spacer.addEventListener 'webkitTransitionEnd', =>
      @remove()

  delete: ->
    queue.enqueue (next) =>
      if @data._id
        xhr.delete '/annotations/'+@data._id, (err, d) =>
          next err
      else next()

  save: ->
    @content.style.color = '#bbb'
    queue.enqueue (next) =>
      if @data._id
        xhr.put '/annotations/'+@data._id, @data, (err, d) =>
          return next err if err
          @content.style.color = ''
          next()
      else
        xhr.post '/annotations', @data, (err, d) =>
          return next err if err
          @content.style.color = ''
          @data._id = d.id
          next()

annotation = (data) ->
  v = new AnnotationView data
  v.$el = v.render()
  v

minHeightForAnnotation = (a) ->
  minY = a.$el.offsetTop + 150
  maxY = Infinity
  p =
    left: a.$el.offsetLeft
    width: a.content.offsetWidth
  for ann in annotations.views when ann isnt a
    w = ann.content.offsetWidth
    l = ann.$el.offsetLeft
    if l < p.left + p.width and l+w >= p.left
      minY = Math.max(minY, ann.$el.offsetTop+ann.$el.offsetHeight)
      maxY = Math.min(maxY, ann.content.offsetTop + ann.$el.offsetTop)
  if maxY isnt Infinity and maxY - a.content.offsetHeight >= a.$el.offsetTop + 150
    maxY - a.$el.offsetTop - a.content.offsetHeight
  else
    minY - a.$el.offsetTop

addAnnotation = (data) ->
  a = annotation data
  mom = moment data.date, 'YYYY-MM-DD'
  a.moment = mom # XXX hm
  p = posForDay(mom)
  p.left += 25; p.top += 51
  a.setPos p
  annotations.addBeforeFirst a, (x) -> x.moment.isBefore(a.moment)
  minY = minHeightForAnnotation a
  a.setHeight minY
  a

newAnnotation = (mom) ->
  for existing_a in annotations.views
    if existing_a.moment.isSame(mom, 'day')
      return existing_a.edit()
  a = addAnnotation text: '', date: mom.format('YYYY-MM-DD')
  a.setHeight 0
  a.edit()
  a.spacer.style.webkitTransition = '200ms'
  minY = minHeightForAnnotation a
  setTimeout ->
    a.setHeight minY

class SpanningAnnotationView extends View
  constructor: (@data) ->
    super()
    @from_mom = moment @data.date, 'YYYY-MM-DD'
    @to_mom = moment(@from_mom).add 'day', @data.span
  zoneForEvent: (ev) ->
    {width} = @getSize()
    offX = ev.pageX - @$el.getBoundingClientRect().left
    if offX <= 5
      'left'
    else if offX >= width - 5
      'right'
  render: ->
    e = tag '.spanning-annotation'
    w = 50 * @to_mom.diff(@from_mom, 'days')
    e.style.width = w + 'px'
    fp = posForDay @from_mom
    fp.top = 100
    fp.left += 25
    e.style.left = fp.left + 'px'
    e.style.top = fp.top + 'px'
    @content = e.appendChild tag '.content'
    @content.textContent = @data.text
    e.addEventListener 'mousemove', (ev) =>
      @$el.style.cursor = switch @zoneForEvent ev
        when 'left', 'right' then 'ew-resize'
        else 'default'
    e.addEventListener 'mousedown', (ev) =>
      ev.preventDefault()
      side = @zoneForEvent ev
      if not side
        return @edit()
      @beginDrag side
    e

  beginDrag: (side) ->
    document.documentElement.style.cursor = 'ew-resize'
    window.addEventListener 'mousemove', resize = (ev) =>
      ev.preventDefault()
      ev.stopPropagation()
      nowX = ev.pageX + sx
      d = dayForWorldX nowX
      if side is 'left'
        @from_mom = d
      else
        @to_mom = d
      @refresh()
    , true
    window.addEventListener 'mouseup', done = (ev) =>
      ev.preventDefault()
      ev.stopPropagation()
      document.documentElement.style.cursor = ''
      window.removeEventListener 'mousemove', resize, true
      window.removeEventListener 'mouseup', done, true
      window.removeEventListener 'blur', done
      @updated()
      @_onDragComplete?()
    , true
    window.addEventListener 'blur', done

  updated: ->
    {left} = @getPos()
    {width} = @getSize()
    @data.date = @from_mom.format('YYYY-MM-DD')
    @data.span = @to_mom.diff(@from_mom, 'day')
    @refresh()
    @save()

  edit: ->
    return if @editing
    @editing = true
    value = @content.textContent
    @content.textContent = ''
    @textArea = @content.appendChild tag 'textarea'
    @textArea.value = value
    @textArea.style.width = '100%'
    makeExpandingArea @textArea
    @textArea.onblur = => @doneEditing()
    @textArea.addEventListener 'input', =>
    @textArea.addEventListener 'keydown', (e) =>
      if e.which is 13 and not e.shiftKey
        e.preventDefault()
        @doneEditing()
    @textArea.focus()

  doneEditing: ->
    return unless @editing
    @editing = false
    value = @data.text = @textArea.value
    if value.length is 0
      @delete()
      @fadeOut()
      return
    else
      @save()
    @content.textContent = value

  save: ->
    @content.style.color = '#bbb'
    queue.enqueue (next) =>
      if @data._id
        xhr.put '/annotations/'+@data._id, @data, (err, d) =>
          return next err if err
          @content.style.color = ''
          next()
      else
        xhr.post '/annotations', @data, (err, d) =>
          return next err if err
          @content.style.color = ''
          @data._id = d.id
          next()
  delete: ->
    queue.enqueue (next) =>
      if @data._id
        xhr.delete '/annotations/'+@data._id, (err, d) =>
          next err
  fadeOut: ->
    @$el.style.webkitTransition = '200ms ease-in'
    @$el.style.width = '0px'
    @$el.style.overflow = 'hidden'
    @$el.addEventListener 'webkitTransitionEnd', =>
      @remove()

addSpanningAnnotation = (data) ->
  a = new SpanningAnnotationView data
  spanning_annotations.add a
  a

## INITIALIZATION ##

calendar = document.body.appendChild tag 'div#calendar'

days = new Layer '.days'
days.setPos top: 300 + (if doMonthBounce then 100 else 0)
months = new Layer '.months'
annotations = new Layer '.annotations'
annotations.setPos top: 300 + (if doMonthBounce then 100 else 0)
spanning_annotations = new Layer '.spanning-annotations'
overlay = new Layer '.overlay'
overlay.add errorMessage

calendar.appendChild l.$el for l in [
  spanning_annotations
  annotations
  days
  months
]
document.body.appendChild overlay.$el

document.addEventListener 'keydown', (e) ->
  return if document.activeElement.tagName isnt 'BODY'
  if e.which == 'T'.charCodeAt(0)
    setScrollX leftForDay(moment(origin).startOf('week').subtract('week', 1))
    updateReified()
, false

xhr.get '/annotations.json', (err, anns) ->
  throw err if err
  for a in anns
    if a.span?
      addSpanningAnnotation a
    else
      addAnnotation a

## SCROLLING ##

origin = moment().startOf('day')
sx = 0

setScrollX = (x) ->
  sx = x
  calendar.style.webkitTransform = 'translateX('+-sx+'px)'

setScrollX leftForDay(moment(origin).startOf('week').subtract('week', 1))

leftmostReifiedDay = moment(origin)
numReifiedDays = 0
reifyDay = (mom) ->
  d = day(mom)
  d.setPos posForDay(mom)
  d

updateReifiedDays = ->
  # TODO: total re-render if overlap is small
  if leftForDay(leftmostReifiedDay) > sx
    while leftForDay(leftmostReifiedDay) > sx - 250
      m = moment(leftmostReifiedDay).add('days', -1)
      d = reifyDay m
      days.addBegin d
      leftmostReifiedDay = m
      numReifiedDays++
  while leftForDay(moment(leftmostReifiedDay).add('day', numReifiedDays)) < sx+innerWidth
    m = moment(leftmostReifiedDay).add('days', numReifiedDays)
    d = reifyDay m
    days.add d
    numReifiedDays++
  if leftForDay(moment(leftmostReifiedDay).add('day', 1)) < sx
    while leftForDay(moment(leftmostReifiedDay).add('day', 1)) < sx - 250
      days.views[0].remove()
      numReifiedDays--
      leftmostReifiedDay.add('day', 1)
  while leftForDay(moment(leftmostReifiedDay).add('day', numReifiedDays-1)) > sx + innerWidth
    days.views[days.views.length-1].remove()
    numReifiedDays--

reifyMonth = (m) ->
  d = month(m)
  d.setPos posForMonth(m)
  d
leftmostReifiedMonth = moment(leftmostReifiedDay).startOf('month')
numReifiedMonths = 0
updateReifiedMonths = ->
  while leftForDay(leftmostReifiedMonth) > sx
    m = moment(leftmostReifiedMonth).add('months', -1)
    d = reifyMonth m
    months.addBegin d
    leftmostReifiedMonth = m
    numReifiedMonths++
  while leftForDay(moment(leftmostReifiedMonth).add('month', numReifiedMonths)) < sx + innerWidth
    m = moment(leftmostReifiedMonth).add('months', numReifiedMonths)
    d = reifyMonth m
    months.add d
    numReifiedMonths++
  while leftForDay(moment(leftmostReifiedMonth).add('month', 1)) < sx
    months.views[0].remove()
    numReifiedMonths--
    leftmostReifiedMonth.add 'month', 1
  while leftForDay(moment(leftmostReifiedMonth).add('month', numReifiedMonths-1)) > sx + innerWidth
    months.views[months.views.length-1].remove()
    numReifiedMonths--

updateReified = ->
  updateReifiedDays()
  updateReifiedMonths()
  displayingMostlyMonth = dayForWorldX(sx+innerWidth/2)
  document.title = displayingMostlyMonth.format('MMMM YYYY') + ' - Continuum'
  # TODO: favicon with current date

updateReified()

window.onmousewheel = (e) ->
  e.preventDefault()
  setScrollX sx-e.wheelDelta
  updateReified()

window.onresize = ->
  updateReified()

window.onscroll = (e) ->
  dx = window.scrollX
  window.scrollTo 0, 0
  setScrollX sx+dx
  updateReified()
  e.preventDefault()


touchHistory = []
touchStart = undefined
scrolling = false

window.addEventListener 'touchstart', (e) ->
  e.preventDefault()
  e.stopPropagation()
  touchStart = {timeStamp: e.timeStamp, touches: (clientX:t.clientX,clientY:t.clientY for t in e.touches)}
  stopGlide()

window.addEventListener 'touchmove', (e) ->
  e.preventDefault()
  {clientX:x, clientY:y} = e.touches[0]
  dx = touchStart.touches[0].clientX - x
  dy = touchStart.touches[0].clientY - y
  if not scrolling
    if Math.abs(dx) >= 10 or Math.abs(dy) >= 10
      scrolling = true
      touchHistory = [{x, y, timeStamp:e.timeStamp}]
      return
  if scrolling
    e.stopPropagation()
    dx = touchHistory[0].x - x
    setScrollX sx+dx
    touchHistory.unshift {x, y, timeStamp:e.timeStamp}
    touchHistory = touchHistory.filter (x) -> e.timeStamp - x.timeStamp <= 100
    updateReified()

window.addEventListener 'touchend', (e) ->
  return unless scrolling
  e.preventDefault()

  touchHistory = touchHistory.filter (x) -> e.timeStamp - x.timeStamp <= 100
  if touchHistory.length
    dt = e.timeStamp - touchHistory[touchHistory.length-1].timeStamp
    dx = e.changedTouches[0].clientX - touchHistory[touchHistory.length-1].x
    velocity = dx/dt # in px/s
    if Math.abs(velocity) >= 1
      glide -velocity
  touchHistory = []
  touchStart = undefined
  scrolling = false

glideAnim = undefined
glide = (vel) ->
  lastFrame = Date.now()
  glideAnim = webkitRequestAnimationFrame f = ->
    glideAnim = webkitRequestAnimationFrame f
    now = Date.now()
    dt = (now - lastFrame)
    lastFrame = now
    return if dt == 0
    dx = vel * dt
    vel *= 0.95
    if Math.abs(vel) < 0.01
      stopGlide()
    console.log dt/1000, vel
    setScrollX sx+dx
    updateReified()
stopGlide = ->
  webkitCancelAnimationFrame glideAnim if glideAnim

## TIMERS ##

everyMinute = ->
  for d in days.views
    if d.isToday != d.moment.isSame(moment(), 'day')
      d.refresh()
  return

do ->
  timeUntilNextMinute = ->
    now = moment()
    moment(now).endOf('minute').diff(now) + 50
  f = ->
    setTimeout ->
      everyMinute()
      f()
    , timeUntilNextMinute()
  f()
