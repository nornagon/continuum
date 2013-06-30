main_layer = document.getElementById('calendar')

tag = (name, text) ->
  parts = name.split /(?=[.#])/ # why yes, i am a ninja
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

textNode = (text) -> document.createTextNode text

class ElementWrapper
  setPos: (r) ->
    if r.left? then @$el.style.left = r.left + 'px'
    if r.top? then @$el.style.top = r.top + 'px'
    return
  setSize: (r) ->
    if r.width? then @$el.style.width = r.width + 'px'
    if r.height? then @$el.style.height = r.height + 'px'
    return

# Layers contain Views.
class Layer extends ElementWrapper
  constructor: (className = '') ->
    @views = []
    @$el = tag className + '.layer'
  add: (view) ->
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
    for v,i in @views
      if cond v
        break
    console.log v, i
    view.layer = @
    @$el.insertBefore view.$el, v?.$el
    @views.splice i, 0, view
    view
  remove: (view) ->
    @$el.removeChild view.$el
    @views = (v for v in @views when v isnt view)
    return

# A View is a description of an HTML element in terms of a function which
# generates it.
class View extends ElementWrapper
  constructor: (@render) ->
    @handlers = {}
    @$el = @render()
  refresh: ->
    newEl = @render()
    for e of @handlers
      for f in e
        newEl.addEventListener ev, f
    @$el.parentNode?.replaceChild(newEl, @$el)
    @$el = newEl
  remove: ->
    @layer?.remove @

  on: (ev, fn) ->
    (@handlers[ev] ||= []).push fn
    @$el.addEventListener ev, fn

doMonthBounce = no

day = (m) ->
  new View ->
    d = tag '.day', m.format('ddd')
    num = d.appendChild tag '.number', m.format('D')
    d

dayForWorldX = (x) ->
  moment(origin).add('days', x/50|0)

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

month = (m) ->
  new View ->
    tag '.month', m.format('MMMM YYYY')
posForMonth = (m) ->
  left: leftForDay(m)
  top: 40

annotation = ->
  new View ->
    e = tag '.annotation'
    e.style.height = '150px'
    @contents = e.appendChild tag '.content', 'event'
    e


days = new Layer '.days'
days.setPos top: 300 + (if doMonthBounce then 100 else 0)
months = new Layer
annotations = new Layer
annotations.setPos top: 300 + (if doMonthBounce then 100 else 0)

calendar.appendChild l.$el for l in [
  annotations
  days
  months
]

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
  if mom.isSame(moment(), 'day')
    d.$el.classList.add 'today'
  d.setPos posForDay(mom)
  d.on 'click', ->
    a = annotation()
    a.moment = mom
    p = posForDay(mom)
    p.left += 25; p.top += 51
    a.setPos p
    annotations.addBeforeFirst a, (x) -> x.moment.isAfter(a.moment)
  d


updateReifiedDays = ->
  # TODO: total re-render if overlap is small
  while leftForDay(leftmostReifiedDay) > sx
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
  while leftForDay(moment(leftmostReifiedDay).add('day', 1)) < sx
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

updateReified()

window.onmousewheel = (e) ->
  e.preventDefault()
  setScrollX sx-e.wheelDeltaX
  updateReified()

window.onresize = ->
  updateReified()

window.onkeydown = (e) ->
  if e.which == 'T'.charCodeAt(0)
    setScrollX leftForDay(moment(origin).startOf('week').subtract('week', 1))
    updateReified()
