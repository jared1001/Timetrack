// ==========================================
// TimeTrack Manager - Authentication
// ==========================================


// ------------------------------------------
// Check Current Session
// ------------------------------------------

async function checkSession() {

    const {
        data: { session }
    } = await supabaseClient.auth.getSession();

    // No session
    if (!session) {

        if (!window.location.pathname.endsWith("login.html")) {
            window.location.href = "login.html";
        }

        return;
    }

    // User is logged in
    const user = session.user;

    // If currently on login page,
    // verify role and redirect.
    if (window.location.pathname.endsWith("login.html")) {

        await verifyManagerRole(user.id);

    }

}


// ------------------------------------------
// Login
// ------------------------------------------

async function loginManager(email, password) {

    const message = document.getElementById("loginMessage");

    try {

        message.textContent = "Signing in...";
        message.className = "message";


        const {
            data,
            error
        } = await supabaseClient.auth.signInWithPassword({
            email: email,
            password: password
        });


        if (error) {
            throw error;
        }


        if (!data.user) {
            throw new Error("Login failed.");
        }


        await verifyManagerRole(data.user.id);


    } catch (error) {

        console.error(error);

        message.textContent =
            "Invalid email or password.";

        message.className =
            "message error";

    }

}


// ------------------------------------------
// Verify Manager/Admin Role
// ------------------------------------------

async function verifyManagerRole(userId) {

    try {

        const {
            data: profile,
            error
        } = await supabaseClient
            .from("profiles")
            .select("id, full_name, email, employee_number, role")
            .eq("id", userId)
            .single();


        if (error) {
            throw error;
        }


        if (
            profile.role !== "manager" &&
            profile.role !== "admin"
        ) {

            await supabaseClient.auth.signOut();

            alert(
                "Access denied. Manager or Admin access is required."
            );

            window.location.href = "login.html";

            return;
        }


        // Authorized
        window.location.href = "dashboard.html";


    } catch (error) {

        console.error(
            "Role verification failed:",
            error
        );

        await supabaseClient.auth.signOut();

        alert(
            "Unable to verify your account permissions."
        );

        window.location.href = "login.html";

    }

}


// ------------------------------------------
// Logout
// ------------------------------------------

async function logout() {

    try {

        await supabaseClient.auth.signOut();

        window.location.href = "login.html";

    } catch (error) {

        console.error(
            "Logout error:",
            error
        );

    }

}


// ------------------------------------------
// Login Form
// ------------------------------------------

const loginForm =
    document.getElementById("loginForm");


if (loginForm) {

    loginForm.addEventListener(
        "submit",
        async function (event) {

            event.preventDefault();


            const email =
                document
                    .getElementById("email")
                    .value
                    .trim();


            const password =
                document
                    .getElementById("password")
                    .value;


            await loginManager(
                email,
                password
            );

        }
    );

}


// ------------------------------------------
// Logout Button
// ------------------------------------------

const logoutButton =
    document.getElementById("logoutButton");


if (logoutButton) {

    logoutButton.addEventListener(
        "click",
        logout
    );

}

