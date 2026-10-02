/// Build-time settings. Leave the Supabase values empty to run in demo mode,
/// where rooms live only on this device.
const appName = 'КиноЧат';

/// Project URL and publishable (anon) key from Supabase → Project Settings →
/// API. Both are meant to be shipped inside the app.
const supabaseUrl = '';
const supabaseKey = '';

/// Where the web version is published; used for invite links and as the
/// page origin of the embedded player on Android.
const webAppUrl = 'https://backwardzz.github.io/kinochat/';

const maxRoomMembers = 20;
const maxMessageLength = 1000;

bool get hasServer => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
