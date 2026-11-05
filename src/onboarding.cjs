'use strict';

// Shared validation contract. The backend must independently enforce these rules.
function validateProfile(input = {}, today = new Date()) {
  const errors = {};
  const displayName = String(input.displayName ?? '').trim();
  const birthDate = String(input.birthDate ?? '');
  const locale = input.locale;
  if (displayName.length < 2 || displayName.length > 40) errors.displayName = 'name_length';
  const parsed = /^\d{4}-\d{2}-\d{2}$/.test(birthDate) ? new Date(birthDate + 'T00:00:00Z') : null;
  if (!parsed || !Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== birthDate) {
    errors.birthDate = 'invalid_date';
  } else {
    const current = today.toISOString().slice(0, 10);
    let age = Number(current.slice(0, 4)) - Number(birthDate.slice(0, 4));
    if (current.slice(5) < birthDate.slice(5)) age--;
    if (age < 18 || age > 120) errors.birthDate = 'adults_only';
  }
  if (!['fr', 'en'].includes(locale)) errors.locale = 'unsupported_language';
  if (input.acceptedRules !== true) errors.acceptedRules = 'rules_required';
  return { valid: Object.keys(errors).length === 0, errors,
    value: { displayName, birthDate, locale } };
}

function activeVenueSession(session, now = Date.now()) {
  return Boolean(session && session.venueId && !session.endedAt &&
    Number.isFinite(Date.parse(session.expiresAt)) && Date.parse(session.expiresAt) > now);
}

function canShareVenue(viewer, other, now = Date.now()) {
  return activeVenueSession(viewer, now) && activeVenueSession(other, now) &&
    viewer.venueId === other.venueId;
}

module.exports = { validateProfile, activeVenueSession, canShareVenue };
