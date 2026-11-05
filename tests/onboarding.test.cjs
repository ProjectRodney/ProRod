const test = require('node:test');
const assert = require('node:assert/strict');
const { validateProfile, activeVenueSession, canShareVenue } = require('../src/onboarding.cjs');
const today = new Date('2026-11-05T12:00:00Z');
const profile = {displayName:'  Alex  ', birthDate:'2000-01-01',locale:'fr',acceptedRules:true};
test('profile normalizes name and strips unrelated authorization fields', () => {
  const result = validateProfile({...profile,admin:true,paid:true},today);
  assert.equal(result.valid,true);
  assert.deepEqual(result.value,{displayName:'Alex',birthDate:'2000-01-01',locale:'fr'});
});
test('age boundary and invalid calendar dates fail closed', () => {
  for (const date of ['2008-11-06','2026-02-30','invalid','2027-01-01']) {
    assert.equal(validateProfile({...profile,birthDate:date},today).valid,false);
  }
  assert.equal(validateProfile({...profile,birthDate:'2008-11-05'},today).valid,true);
});
test('rules agreement and supported language are required', () => {
  assert.equal(validateProfile({...profile,acceptedRules:false},today).valid,false);
  assert.equal(validateProfile({...profile,locale:'xx'},today).valid,false);
});
test('venue visibility expires exactly at server expiry and excludes other venues', () => {
  const now = today.getTime();
  const live = {venueId:'a',expiresAt:'2026-11-05T13:00:00Z'};
  assert.equal(canShareVenue(live,{...live},now),true);
  assert.equal(canShareVenue(live,{...live,venueId:'b'},now),false);
  assert.equal(activeVenueSession({...live,expiresAt:today.toISOString()},now),false);
  assert.equal(activeVenueSession({...live,endedAt:today.toISOString()},now),false);
  assert.equal(activeVenueSession({...live,expiresAt:'bad'},now),false);
});
