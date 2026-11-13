function advance(pending, rows, previousY, currentY, now) {
  var next = {}
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    if (row.bottom > currentY) continue
    if (Object.prototype.hasOwnProperty.call(pending, row.id)) {
      next[row.id] = pending[row.id]
    } else if (currentY > previousY && row.bottom > previousY) {
      next[row.id] = now
    }
  }
  return next
}

function ready(pending, now) {
  return Object.keys(pending).filter(function(id) {
    return now - pending[id] > 1000
  })
}
