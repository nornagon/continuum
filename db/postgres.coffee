{Client} = require 'pg'

client = new Client

client.connect()

migrate = ->
  try
    await client.query('BEGIN')
    await client.query('CREATE TABLE IF NOT EXISTS users (_id serial, email varchar, created_at timestamp)')
    await client.query('CREATE TABLE IF NOT EXISTS annotations (_id serial, user_id integer, text text, date date, span integer)')
    await client.query('COMMIT')
  catch e
    await client.query('ROLLBACK')
    throw e

migrate()

exports.getUserForEmail = (email, cb) ->
  client.query 'SELECT * FROM users WHERE email = $1 LIMIT 1', [email], (err, res) ->
    return cb err if err
    if res.rows.length < 1
      return cb 'user not found'
    cb null, res.rows[0]

exports.getUser = (id, cb) ->
  client.query 'SELECT * FROM users WHERE _id = $1 LIMIT 1', [email], (err, res) ->
    return cb err if err
    if res.rows.length < 1
      return cb 'user not found'
    cb null, res.rows[0]

exports.getOrCreateUser = (email, cb) ->
  client.query 'SELECT * FROM users WHERE email = $1 LIMIT 1', [email], (err, res) ->
    return cb err if err
    if res.rows.length >= 1
      return cb null, res.rows[0]
    client.query 'INSERT INTO users (email, created_at) VALUES ($1, NOW()) RETURNING *', (err, res) ->
      return cb err if err
      cb null, res.rows[0]

exports.getAnnotationsForUser = (user_id, cb) ->
  client.query 'SELECT * FROM annotations WHERE user_id = $1', [user_id], (err, res) ->
    return cb err if err
    cb null, res.rows

exports.getAnnotation = (ann_id, cb) ->
  client.query 'SELECT * FROM annotations WHERE _id = $1 LIMIT 1', [ann_id], (err, res) ->
    return cb err if err
    cb null, res.rows[0]

exports.putAnnotation = (ann, cb) ->
  if ann._id
    client.query 'UPDATE annotations SET text = $2, date = $3, span = $4 WHERE _id = $1 RETURNING *', [ann._id, ann.text, ann.date, ann.span], (err, res) ->
      return cb err if err
      cb null, res.rows[0]
  else
    client.query 'INSERT INTO annotations (user_id, text, date, span) VALUES ($1, $2, $3, $4) RETURNING *', [ann.user_id, ann.text, ann.date, ann.span], (err, res) ->
      return cb err if err
      cb null, res.rows[0]

exports.delAnnotation = (id, cb) ->
  client.query 'DELETE FROM annotations WHERE _id = $1 RETURNING *', [id], (err, res) ->
    return cb err if err
    cb null, res.rows[0]
