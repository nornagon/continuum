fs = require 'fs'
express = require 'express'
request = require 'request'
moment = require './static/assets/moment'

config_defaults =
  db: 'couch'
  audience: 'http://localhost:8888'
  secret: require('crypto').randomBytes(64).toString()

config = try
  JSON.parse fs.readFileSync "#{__dirname}/config.json"
catch e
  {}
config.__proto__ = config_defaults

db = require "./db/#{config.db}"

app = express()

app.engine 'html', require('consolidate').toffee
app.set 'view engine', 'html'
app.set 'views', __dirname + '/views'

app.use express.logger 'dev'
app.use express.static __dirname + '/static'
app.use express.bodyParser()
app.use express.cookieParser()
session = express.cookieSession secret:config.secret, proxy:true
app.use app.router


# Middleware to make sure a user is logged in before allowing them to access the page.
# You could improve this by setting a redirect URL to the login page, and then redirecting back
# after they've authenticated.
restrict = (req, res, next) ->
  return next() if req.session.user
  res.redirect '/login'

app.post '/auth', session, (req, res, next) ->
  return next(new Error 'No assertion in body') unless req.body.assertion

  # Persona has given us an assertion, which needs to be verified. The easiest way to verify it
  # is to get mozilla's public verification service to do it.
  #
  # The audience field is hardcoded, and does not use the HTTP headers or anything. See:
  # https://developer.mozilla.org/en-US/docs/Persona/Security_Considerations
  request.post 'https://verifier.login.persona.org/verify',
    form:
      audience: config.audience
      assertion: req.body.assertion
    (err, _, body) ->
      return next(err) if err

      try
        data = JSON.parse body
      catch e
        return next(e)

      return next(new Error data.reason) unless data.status is 'okay'

      # Login worked.
      db.getOrCreateUser data.email, (err, user) ->
        req.session.user = user
        res.redirect '/'

# We need to do 2 things during logout:
# - Delete the user's logged in status from their session object (ie, record they've been
#   logged out on the server)
# - Tell persona they've been logged out in the browser.
app.get '/logout', session, (req, res, next) ->
  res.render 'logout', user: req.session?.user
  delete req.session.user if req.session
  req.session = null

# The login page needs CSRF (cross-site request forging) protection. The token is generated by
# the express.csrf() middleware, its injected into the hidden login form and then automatically
# checked when the login form is submitted.
app.get '/login', session, (req, res) ->
  if app.get('env') is 'development' and config.dev_email
    db.getUserForEmail config.dev_email, (err, user) ->
      throw err if err
      req.session.user = user
      res.redirect '/'
    return
  res.render 'login', csrf: req.session._csrf, user: req.session.user

app.get '/', session, (req, res) ->
  if req.session?.user
    res.render 'index', csrf: req.session._csrf, user: req.session.user
  else
    res.redirect '/login'

app.get '/annotations.json', session, restrict, (req, res, next) ->
  db.getAnnotationsForUser req.session.user._id, (err, anns) ->
    return next() if err
    res.end JSON.stringify anns

app.post '/annotations', session, restrict, (req, res, next) ->
  db.putAnnotation {
    type: 'annotation'
    user_id: req.session.user._id
    text: req.body.text
    date: req.body.date
    span: req.body.span
  }, (err, d) ->
    return res.end JSON.stringify err if err
    res.end JSON.stringify d

app.put '/annotations/:id', session, restrict, (req, res, next) ->
  db.getAnnotation req.params.id, (err, d) ->
    return res.end JSON.stringify ok: no, error: 'no such annotation' if err or d.user_id isnt req.session.user._id
    db.putAnnotation {
      _id: req.body._id
      type: 'annotation'
      user_id: req.session.user._id
      text: req.body.text
      date: req.body.date
      span: req.body.span
    }, (err, d) ->
      return res.end JSON.stringify err if err
      res.end JSON.stringify d

app.delete '/annotations/:id', session, restrict, (req, res, next) ->
  db.getAnnotation req.params.id, (err, d) ->
    return res.end JSON.stringify ok: no, error: 'no such annotation' if err or d.user_id isnt req.session.user._id
    db.delAnnotation req.params.id, (err, r) ->
      return res.end JSON.stringify err if err
      res.end JSON.stringify r

uuid = ->
  'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace /[xy]/g, (c) ->
    r = Math.random()*16|0
    (if c == 'x' then r else (r&0x3|0x8)).toString 16

formatDate = (datetime, offset = new Date().getTimezoneOffset()) ->
  pad = (n) ->
    n = parseInt(n)
    if n < 10 then '0' + n else '' + n

  d = new Date(datetime)
  d.setUTCMinutes(d.getUTCMinutes() - offset)

  [
    d.getUTCFullYear()
    pad(d.getUTCMonth() + 1)
    pad(d.getUTCDate()) + 'T'
    pad(d.getUTCHours())
    pad(d.getUTCMinutes())
    pad(d.getUTCSeconds())
  ].join('')

app.get '/calendar/:id.ics', (req, res) ->
  db.getAnnotationsForUser req.params.id, (err, anns) ->
    return res.end JSON.stringify ok: no, error: 'no such calendar' if err
    res.setHeader 'Content-type', 'text/calendar'
    res.write 'BEGIN:VCALENDAR\n'
    res.write 'CALSCALE:GREGORIAN\n'
    res.write 'METHOD:PUBLISH\n'
    events = for a in anns
      res.write 'BEGIN:VEVENT\n'
      res.write 'UID:' + uuid() + '\n'
      res.write 'DTSTAMP:' + formatDate(new Date()) + '\n'
      res.write 'DTSTART;VALUE=DATE:' + moment(a.date).format('YYYYMMDD') + '\n'
      res.write 'DTEND;VALUE=DATE:' + moment(a.date).add('d',1).format('YYYYMMDD') + '\n'
      res.write 'SUMMARY:' + a.text.replace(/\n/g,'\\n') + '\n'
      res.write 'END:VEVENT\n'
    res.end 'END:VCALENDAR\n'
    res.end JSON.stringify anns

port = process.argv[2] ? 8888
app.listen port
console.log "Listening on http://localhost:#{port}"
