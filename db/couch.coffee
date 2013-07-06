cradle = require 'cradle'
couch = new cradle.Connection 'http://localhost', 5984, {
  cache: false
  raw: false
}

designs =
  users:
    by_email: (doc) ->
      if doc.type is 'user'
        emit doc.email, null
  annotations:
    by_user: (doc) ->
      if doc.type is 'annotation'
        emit [doc.user_id, doc.date], null

pushDesigns = (db) ->
	for d of designs
		do (d) ->
      for v of designs[d]
        if typeof designs[d][v] is 'function'
          designs[d][v] = { map: designs[d][v] }
      db.get '_design/' + d, (err, res) ->
        # if (err) { console.log(err); return }
        data = JSON.stringify designs[d], (k, val) ->
          if typeof val is 'function'
            val.toString()
          else
            val
        if res and data == JSON.stringify(res.views)
          #console.info("_design/" + d + " up to date (rev " + res._rev + ")")
        else
          db.save '_design/' + d, designs[d], (err, res) ->
            throw err if err
            console.info "Updated " + res.id + " (rev " + res.rev + ")"

db = couch.database 'continuum'
db.exists (err, exists) ->
  throw err if err
  if not exists
    db.create()
  pushDesigns db

exports.getUserForEmail = (email, cb) ->
  db.view 'users/by_email', {
    include_docs: true
    startkey: email
    endkey: email
  }, (err, users) ->
    return cb err if err
    if users.length < 1
      return cb 'user not found'
    cb null, users[0].doc

exports.getUser = (id, cb) ->
  db.get id, cb

exports.getOrCreateUser = (email, cb) ->
  db.view 'users/by_email', {
    include_docs: true
    startkey: email
    endkey: email
  }, (err, users) ->
    return cb err if err
    if users.length >= 1
      return cb null, users[0].doc
    db.save user = {
      type: 'user'
      email: email
      created_at: (new Date).toISOString()
    }, (err, r) ->
      return cb err if err
      u = JSON.parse JSON.stringify db.cache.get r.id
      u._created = true
      cb null, u

exports.getAnnotationsForUser = (user_id, cb) ->
  db.view 'annotations/by_user', {
    include_docs: true
    startkey: [user_id]
    endkey: [user_id, {}]
  }, (err, anns) ->
    return cb err if err
    cb null, (a.doc for a in anns)

exports.getAnnotation = (ann_id, cb) ->
  db.get ann_id, cb

exports.putAnnotation = (ann, cb) ->
  db.save ann, (err, r) ->
    return cb err if err
    cb null, r

exports.delAnnotation = (id, cb) ->
  db.head id, (err, d) ->
    return cb err if err
    db.remove id, d.etag.slice(1, -1), (err, r) ->
      return cb err if err
      cb null, r
