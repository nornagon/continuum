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
  constructor: (className) ->
    @views = []
    @$el = tag className
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
  remove: (view) ->
    @$el.removeChild view.$el
    @views = (v for v in @views when v isnt view)
    return

# A View is a description of an HTML element in terms of a function which
# generates it.
class View extends ElementWrapper
  constructor: (@render) ->
    @$el = @render()
  refresh: ->
    newEl = @render()
    @$el.parentNode?.replaceChild(newEl, @$el)
    @$el = newEl
  remove: ->
    @layer?.remove @

doMonthBounce = no

day = (m) ->
  new View ->
    d = tag '.day'
    d.appendChild textNode m.format('ddd')
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
    j = m.date()/m.endOf('month').date()
    monthBounce = -Math.sin(j*Math.PI) * 150
    v + monthBounce
  else
    v

leftForDay = (m) ->
  m.diff(origin, 'day')*50

posForDay = (m) ->
  left: leftForDay(m)
  top: topForDay(m)

daysParent = new Layer '.days'
days = daysParent.add new Layer '.origin'
days.setPos top: 300 + (if doMonthBounce then 100 else 0)
calendar.appendChild daysParent.$el

origin = moment().startOf('day')
sx = 0

setScrollX = (x) ->
  sx = x
  days.$el.style.webkitTransform = 'translateX('+-sx+'px)'

setScrollX leftForDay(moment(origin).startOf('week').subtract('week', 1))

leftmostReifiedDay = moment(origin)
numReifiedDays = 0
reifyDay = (m) ->
  d = day(m)
  if m.isSame(moment(), 'day')
    d.$el.classList.add 'today'
  d.setPos posForDay(m)
  d

updateReifiedDays = ->
  while leftForDay(leftmostReifiedDay) > sx
    m = moment(leftmostReifiedDay).add('days',-1)
    d = reifyDay m
    days.addBegin d
    leftmostReifiedDay = m
    numReifiedDays++
  while leftForDay(moment(leftmostReifiedDay).add('day', numReifiedDays)) < sx+innerWidth
    m = moment(leftmostReifiedDay).add('days', numReifiedDays)
    d = reifyDay m
    days.add d
    numReifiedDays++
  while leftForDay(leftmostReifiedDay) + 50 < sx
    days.views[0].remove()
    numReifiedDays--
    leftmostReifiedDay.add('day', 1)
  while numReifiedDays*50 > innerWidth+100
    days.views[days.views.length-1].remove()
    numReifiedDays--

updateReifiedDays()

window.onmousewheel = (e) ->
  setScrollX sx-e.wheelDeltaX
  updateReifiedDays()
  e.preventDefault()

window.onresize = ->
  updateReifiedDays()

window.onkeydown = (e) ->
  if e.which == 'T'.charCodeAt(0)
    setScrollX leftForDay(moment(origin).startOf('week').subtract('week', 1))
    updateReifiedDays()
