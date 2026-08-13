function normalizePhone(phone) {
  return String(phone || '').trim();
}

function isValidPhone(phone) {
  return /^1\d{10}$/.test(normalizePhone(phone));
}

module.exports = { normalizePhone, isValidPhone };
