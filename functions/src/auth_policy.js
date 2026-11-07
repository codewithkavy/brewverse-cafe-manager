const TEST_PROJECT = 'brewverse-security-tests';

function verifiedIdentity(auth, env = process.env) {
  if (!auth || typeof auth.uid !== 'string' || !auth.uid.trim()) return false;
  const project = env.GCLOUD_PROJECT || env.GOOGLE_CLOUD_PROJECT;
  const localAuth = /^(127\.0\.0\.1|localhost|\[::1\]):\d+$/.test(env.FIREBASE_AUTH_EMULATOR_HOST || '');
  // Only the isolated project plus an explicit loopback Auth emulator permits
  // legacy local test users without verified email. No client claim enables it.
  if (project === TEST_PROJECT && localAuth) return true;
  const token = auth.token || {};
  if (token.email_verified === true && typeof token.email === 'string' && token.email.includes('@')) return true;
  return token.firebase?.sign_in_provider === 'phone' &&
    typeof token.phone_number === 'string' && /^\+[1-9]\d{7,14}$/.test(token.phone_number);
}

module.exports = { verifiedIdentity };
