const SUPABASE_URL = "https://bkmdeofbhayybxeqiixa.supabase.co";

const SUPABASE_PUBLISHABLE_KEY =
    "sb_publishable_tBWyIcoSdXCaaYmAgpSPLA_c_0RFl1G";

// Replace this with the inbox managed by your IT/account administrator before
// deploying. Do not request or send passwords through this email flow.
const IT_SUPPORT_EMAIL = "replace-with-your-it-email@example.com";

// Create Supabase client
const supabaseClient = window.supabase.createClient(
    SUPABASE_URL,
    SUPABASE_PUBLISHABLE_KEY
);

console.log("TimeTrack Manager: Supabase initialized.");

async function testSupabaseConnection() {
    const { data, error } = await supabaseClient.auth.getSession();

    if (error) {
        console.error("Supabase connection failed:", error);
        return;
    }

    console.log("Supabase connected successfully!");
    console.log("Current session:", data.session);
}

testSupabaseConnection();
