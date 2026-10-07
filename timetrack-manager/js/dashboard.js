// ==========================================
// TimeTrack Manager - Dashboard
// ==========================================

let loadedLeaveRequests = [];
let qrAttendanceSchemaAvailable = true;

const EMPLOYEE_NAME_COLLATOR = new Intl.Collator(undefined, {
    sensitivity: "base",
    numeric: true
});
const LEAVE_STATUS_ORDER = { pending: 0, approved: 1, rejected: 2 };

const NCR_DAILY_MINIMUM_WAGE = 755;
const STANDARD_WORKDAY_HOURS = 8;
const HOURLY_MINIMUM_WAGE = NCR_DAILY_MINIMUM_WAGE / STANDARD_WORKDAY_HOURS;
const STANDARD_BREAK_MINUTES = 60;

async function loadDashboard() {

    try {

        const {
            data: { session }
        } = await supabaseClient.auth.getSession();


        if (!session) {

            window.location.href = "login.html";

            return;

        }


        const userId = session.user.id;


        // Get employee profile
        const {
            data: profile,
            error
        } = await supabaseClient
            .from("profiles")
            .select(
                "id, full_name, email, employee_number, role"
            )
            .eq("id", userId)
            .single();


        if (error) {
            throw error;
        }


        // Security check
        if (
            profile.role !== "manager" &&
            profile.role !== "admin"
        ) {

            await supabaseClient.auth.signOut();

            window.location.href = "login.html";

            return;

        }


        // Display manager information

        document.getElementById(
            "managerName"
        ).textContent =
            profile.full_name || "Manager";


        document.getElementById(
            "managerEmail"
        ).textContent =
            profile.email || session.user.email;

        const managerName = profile.full_name || "Manager";
        const firstName = managerName.trim().split(/\s+/)[0];
        const sidebarName = document.getElementById("managerSidebarName");
        const sidebarRole = document.getElementById("managerSidebarRole");
        const dashboardFirstName = document.getElementById("dashboardManagerFirstName");

        if (sidebarName) sidebarName.textContent = managerName;
        if (sidebarRole) sidebarRole.textContent = profile.role + " account";
        if (dashboardFirstName) dashboardFirstName.textContent = firstName;

        setupItAccessRequest(profile);

        await loadEmployees();
        await loadDashboardSummary();


    } catch (error) {

        console.error(
            "Dashboard loading error:",
            error
        );

    }

}

function setupItAccessRequest(profile) {

    const button = document.getElementById("contactItButton");

    if (!button) return;

    button.addEventListener("click", function () {
        if (!IT_SUPPORT_EMAIL || IT_SUPPORT_EMAIL.includes("replace-with")) {
            alert("IT support email has not been configured yet.");
            return;
        }

        const subject = "TimeTrack account access request";
        const body = [
            "Hello IT,",
            "",
            "I need help with TimeTrack account access.",
            `Name: ${profile.full_name || ""}`,
            `Work email: ${profile.email || ""}`,
            `Employee number: ${profile.employee_number || ""}`,
            `Current role: ${profile.role || ""}`,
            "Requested access or change:",
            "Business reason:",
            "",
            "Please do not send passwords by email."
        ].join("\n");

        window.location.href = `mailto:${encodeURIComponent(IT_SUPPORT_EMAIL)}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
    });

}


async function loadDashboardSummary() {

    try {
        const now = new Date();
        const today = [
            now.getFullYear(),
            String(now.getMonth() + 1).padStart(2, "0"),
            String(now.getDate()).padStart(2, "0")
        ].join("-");
        const [attendanceResult, leaveResult] = await Promise.all([
            supabaseClient
                .from("attendance")
                .select("id", { count: "exact", head: true })
                .eq("date", today),
            supabaseClient
                .from("leave_requests")
                .select("id", { count: "exact", head: true })
                .eq("status", "pending")
        ]);

        if (attendanceResult.error) throw attendanceResult.error;
        if (leaveResult.error) throw leaveResult.error;

        updateReportMetric("presentToday", attendanceResult.count || 0);
        updateReportMetric("pendingLeaveCount", leaveResult.count || 0);
    } catch (error) {
        console.error("Dashboard summary loading error:", error);
    }

}


// ------------------------------------------
// Section switching
// ------------------------------------------

function showSection(sectionId) {

    document.querySelectorAll(".portal-section").forEach(function (section) {
        const isActive = section.id === sectionId;

        section.hidden = !isActive;
        section.classList.toggle("active-section", isActive);
    });

    document.querySelectorAll(".nav-link").forEach(function (link) {
        link.classList.toggle("active", link.dataset.section === sectionId);
    });

    if (sectionId === "attendanceSection") {
        loadAttendance();
    }

    if (sectionId === "qrSection") {
        document.getElementById("qrAction")?.focus();
    }

    if (sectionId === "leaveSection") {
        loadLeaveRequests();
    }

    if (sectionId === "reportsSection") {
        loadReports();
    }

}


function setupAttendanceQrGenerator() {
    const button = document.getElementById("generateAttendanceQrButton");
    const action = document.getElementById("qrAction");

    if (button) button.addEventListener("click", generateAttendanceQr);
    if (action) action.addEventListener("change", updateQrGeneratorFields);
    updateQrGeneratorFields();
}


function updateQrGeneratorFields() {
    const isTimeIn = document.getElementById("qrAction")?.value === "time_in";
    const shiftPayType = document.getElementById("shiftPayTypeFieldset");
    const overtimePayType = document.getElementById("overtimePayTypeFieldset");

    if (shiftPayType) shiftPayType.hidden = !isTimeIn;
    if (overtimePayType) overtimePayType.hidden = isTimeIn;
}


async function generateAttendanceQr() {
    const button = document.getElementById("generateAttendanceQrButton");
    const status = document.getElementById("attendanceQrStatus");
    const action = document.getElementById("qrAction")?.value;
    const shiftType = document.querySelector("input[name='qrShiftType']:checked")?.value;
    const payType = document.querySelector("input[name='qrPayType']:checked")?.value;
    const overtimePayType = document.querySelector("input[name='qrOvertimePayType']:checked")?.value;

    if (
        !button ||
        !status ||
        !["time_in", "overtime_in", "overtime_out"].includes(action) ||
        !["day", "night"].includes(shiftType) ||
        !["normal", "double"].includes(payType) ||
        !["normal", "double"].includes(overtimePayType)
    ) return;

    button.disabled = true;
    status.textContent = "Generating a secure code...";
    document.getElementById("attendanceQrPanel").hidden = true;
    document.getElementById("attendanceQrCanvas").replaceChildren();

    try {
        const { data, error } = await supabaseClient.rpc("create_attendance_qr", {
            p_qr_action: action,
            p_shift_type: shiftType,
            p_pay_type: payType,
            p_overtime_pay_type: overtimePayType
        });

        if (error) throw error;

        const session = Array.isArray(data) ? data[0] : data;
        if (!session?.token) throw new Error("The server did not return a QR token.");
        if (typeof window.QRCode !== "function") {
            throw new Error("The QR generator did not load. Check the portal internet connection and reload.");
        }

        const qrContainer = document.getElementById("attendanceQrCanvas");
        qrContainer.replaceChildren();
        new window.QRCode(qrContainer, {
            width: 260,
            height: 260,
            text: JSON.stringify({
                type: "timetrack_attendance",
                token: session.token
            }),
            colorDark: "#14202b",
            colorLight: "#ffffff",
            correctLevel: window.QRCode.CorrectLevel.H
        });

        const actionLabels = {
            time_in: "Shift Time In",
            overtime_in: "Overtime In",
            overtime_out: "Overtime Out"
        };
        document.getElementById("attendanceQrPayMode").textContent =
            action === "time_in"
                ? (payType === "double" ? "Double-pay shift" : "Regular-pay shift")
                : (overtimePayType === "double" ? "Double-rate overtime" : "Regular overtime");
        document.getElementById("attendanceQrShiftType").textContent =
            shiftType === "night" ? "Night shift" : "Day shift";
        document.getElementById("attendanceQrScanNote").textContent =
            `Employees scan this ${actionLabels[action]} code in the TimeTrack app.`;
        document.getElementById("attendanceQrExpiry").textContent =
            `Valid until ${new Date(session.expires_at).toLocaleString()}`;
        document.getElementById("attendanceQrPanel").hidden = false;
        status.textContent = `${actionLabels[action]} QR is active. Earlier codes of this type are disabled.`;
    } catch (error) {
        console.error("Attendance QR generation error:", error);
        const errorMessage = error?.message || "";
        const isMissingQrRpc = error?.code === "PGRST202" ||
            /could not find the function.*create_attendance_qr/i.test(errorMessage);
        status.textContent = isMissingQrRpc
            ? "The QR database update is missing. Apply supabase/migrations/202610070008_shift_qr_attendance.sql to this Supabase project, then reload the portal."
            : errorMessage || "Unable to generate a QR code.";
    } finally {
        button.disabled = false;
    }
}


// ------------------------------------------
// Load Reports
// ------------------------------------------

async function loadReports() {

    const tableBody = document.getElementById("reportTableBody");

    if (!tableBody) {
        return;
    }

    tableBody.innerHTML = `
        <tr>
            <td colspan="9">Loading reports...</td>
        </tr>
    `;

    try {
        const [profilesResult, initialAttendanceResult, leaveResult] = await Promise.all([
            supabaseClient
                .from("profiles")
                .select("id, full_name, employee_number")
                .eq("role", "employee")
                .order("full_name", { ascending: true }),
            supabaseClient
                .from("attendance")
                .select("user_id, date, time_in, break_in, break_out, time_out, overtime_in, overtime_out, pay_type, overtime_pay_type"),
            supabaseClient
                .from("leave_requests")
                .select("status")
        ]);

        if (profilesResult.error) throw profilesResult.error;
        if (leaveResult.error) throw leaveResult.error;

        let attendanceResult = initialAttendanceResult;
        if (attendanceResult.error && isMissingQrAttendanceSchema(attendanceResult.error)) {
            attendanceResult = await supabaseClient
                .from("attendance")
                .select("user_id, date, time_in, break_in, break_out, time_out");
            setQrAttendanceSchemaStatus(false);
        } else if (attendanceResult.error) {
            throw attendanceResult.error;
        } else {
            setQrAttendanceSchemaStatus(true);
        }
        if (attendanceResult.error) throw attendanceResult.error;

        const profiles = sortEmployeesAlphabetically(profilesResult.data || []);
        const attendance = attendanceResult.data || [];
        const leaveRequests = leaveResult.data || [];
        const attendanceByUser = new Map();
        const now = new Date();
        const periodTotals = {
            dailyMinutes: 0,
            weeklyMinutes: 0,
            monthlyMinutes: 0,
            monthlyOverbreakMinutes: 0,
            monthlyOvertimeMinutes: 0,
            monthlyRegularOvertimeMinutes: 0,
            monthlyDoubleOvertimeMinutes: 0
        };

        attendance.forEach(function (record) {
            const summary = attendanceByUser.get(record.user_id) || {
                records: 0,
                completed: 0,
                workMinutes: 0,
                regularOvertimeMinutes: 0,
                doubleOvertimeMinutes: 0,
                overbreakMinutes: 0
            };

            summary.records += 1;
            const workMinutes = calculateWorkMinutes(record);
            const overtimeMinutes = calculateOvertimeMinutes(record);
            const overbreakMinutes = calculateOverbreakMinutes(record);
            const recordDate = parseAttendanceDate(record.date);

            summary.workMinutes += workMinutes;
            summary.regularOvertimeMinutes +=
                record.overtime_pay_type === "double" ? 0 : overtimeMinutes;
            summary.doubleOvertimeMinutes +=
                record.overtime_pay_type === "double" ? overtimeMinutes : 0;
            summary.overbreakMinutes += overbreakMinutes;

            if (record.time_out != null) summary.completed += 1;
            if (recordDate) {
                if (isSameDay(recordDate, now)) periodTotals.dailyMinutes += workMinutes;
                if (isSameWeek(recordDate, now)) periodTotals.weeklyMinutes += workMinutes;
                if (recordDate.getFullYear() === now.getFullYear() && recordDate.getMonth() === now.getMonth()) {
                    periodTotals.monthlyMinutes += workMinutes;
                    periodTotals.monthlyOverbreakMinutes += overbreakMinutes;
                    periodTotals.monthlyOvertimeMinutes += overtimeMinutes;
                    periodTotals.monthlyRegularOvertimeMinutes +=
                        record.overtime_pay_type === "double" ? 0 : overtimeMinutes;
                    periodTotals.monthlyDoubleOvertimeMinutes +=
                        record.overtime_pay_type === "double" ? overtimeMinutes : 0;
                }
            }

            attendanceByUser.set(record.user_id, summary);
        });

        updateReportMetric("reportEmployeeCount", profiles.length);
        updateReportMetric("reportAttendanceCount", attendance.length);
        updateReportMetric(
            "reportCompletedCount",
            attendance.filter(function (record) {
                return record.time_out != null;
            }).length
        );
        updateReportMetric(
            "reportPendingLeaveCount",
            leaveRequests.filter(function (request) {
                return request.status === "pending";
            }).length
        );
        updateReportMetric("reportDailyHours", formatReportHours(periodTotals.dailyMinutes));
        updateReportMetric("reportWeeklyHours", formatReportHours(periodTotals.weeklyMinutes));
        updateReportMetric("reportMonthlyHours", formatReportHours(periodTotals.monthlyMinutes));
        updateReportMetric(
            "reportOvertimeHours",
            qrAttendanceSchemaAvailable ? formatReportHours(periodTotals.monthlyOvertimeMinutes) : "Apply database update"
        );
        updateReportMetric(
            "reportRegularOvertimeHours",
            qrAttendanceSchemaAvailable ? formatReportHours(periodTotals.monthlyRegularOvertimeMinutes) : "Not available"
        );
        updateReportMetric(
            "reportDoubleOvertimeHours",
            qrAttendanceSchemaAvailable ? formatReportHours(periodTotals.monthlyDoubleOvertimeMinutes) : "Not available"
        );
        updateReportMetric(
            "reportMonthlyPay",
            formatCurrency((periodTotals.monthlyMinutes / 60) * HOURLY_MINIMUM_WAGE)
        );

        renderReportRows(profiles, attendanceByUser, tableBody);

    } catch (error) {
        console.error("Reports loading error:", error);
        tableBody.innerHTML = `
            <tr>
                <td colspan="9">Unable to load reports right now.</td>
            </tr>
        `;
    }

}


function updateReportMetric(elementId, value) {

    const element = document.getElementById(elementId);

    if (element) {
        element.textContent = value;
    }

}


function isMissingQrAttendanceSchema(error) {
    const message = `${error?.message || ""} ${error?.details || ""}`;
    return error?.code === "PGRST204" ||
        error?.code === "42703" ||
        /column.{0,80}(shift_type|pay_type|overtime_in|overtime_out|overtime_pay_type)|(shift_type|pay_type|overtime_in|overtime_out|overtime_pay_type).{0,80}column/i.test(message);
}


function setQrAttendanceSchemaStatus(isAvailable) {
    qrAttendanceSchemaAvailable = isAvailable;
    const reportNotice = document.getElementById("reportQrMigrationNotice");
    const attendanceNotice = document.getElementById("attendanceQrMigrationNotice");

    if (reportNotice) reportNotice.hidden = isAvailable;
    if (attendanceNotice) attendanceNotice.hidden = isAvailable;
}


function renderReportRows(profiles, attendanceByUser, tableBody) {

    if (profiles.length === 0) {
        tableBody.innerHTML = `
            <tr>
                <td colspan="9">No employees registered yet.</td>
            </tr>
        `;
        return;
    }

    tableBody.innerHTML = profiles.map(function (profile) {
        const summary = attendanceByUser.get(profile.id) || {
            records: 0,
            completed: 0,
            workMinutes: 0,
            regularOvertimeMinutes: 0,
            doubleOvertimeMinutes: 0,
            overbreakMinutes: 0
        };

        return `
            <tr>
                <td>${escapeHtml(profile.full_name || "—")}</td>
                <td>${escapeHtml(profile.employee_number || "—")}</td>
                <td>${summary.records}</td>
                <td>${summary.completed}</td>
                <td>${formatReportHours(summary.workMinutes)}</td>
                <td>${qrAttendanceSchemaAvailable ? formatReportHours(summary.regularOvertimeMinutes) : "—"}</td>
                <td>${qrAttendanceSchemaAvailable ? formatReportHours(summary.doubleOvertimeMinutes) : "—"}</td>
                <td>${formatCurrency((summary.workMinutes / 60) * HOURLY_MINIMUM_WAGE)}</td>
                <td>${formatReportOverbreak(summary.overbreakMinutes)}</td>
            </tr>
        `;
    }).join("");

}


function parseAttendanceDate(value) {

    if (!value) return null;

    const parts = value.split("-").map(Number);
    const date = parts.length === 3
        ? new Date(parts[0], parts[1] - 1, parts[2])
        : new Date(value);

    return Number.isNaN(date.getTime()) ? null : date;

}


function parseAttendanceTimestamp(value) {
    if (!value) return null;
    const timestamp = new Date(value);
    return Number.isNaN(timestamp.getTime()) ? null : timestamp;
}


function calculateWorkMinutes(record) {

    const timeIn = parseAttendanceTimestamp(record.time_in);
    const breakIn = parseAttendanceTimestamp(record.break_in);
    const breakOut = parseAttendanceTimestamp(record.break_out);
    const timeOut = parseAttendanceTimestamp(record.time_out);

    if (!timeIn || !breakIn || !breakOut || !timeOut) return 0;

    const firstWorkPeriod = breakIn.getTime() - timeIn.getTime();
    const secondWorkPeriod = timeOut.getTime() - breakOut.getTime();
    return Math.max(0, Math.round((firstWorkPeriod + secondWorkPeriod) / 60000));

}


function calculateOvertimeMinutes(record) {
    const overtimeIn = parseAttendanceTimestamp(record.overtime_in);
    const overtimeOut = parseAttendanceTimestamp(record.overtime_out);

    if (!overtimeIn || !overtimeOut) return 0;
    return Math.max(0, Math.round((overtimeOut.getTime() - overtimeIn.getTime()) / 60000));
}


function calculateOverbreakMinutes(record) {

    const breakIn = parseAttendanceTimestamp(record.break_in);
    const breakOut = parseAttendanceTimestamp(record.break_out);

    if (!breakIn || !breakOut) return 0;

    const breakMinutes = Math.max(0, Math.round((breakOut.getTime() - breakIn.getTime()) / 60000));
    return Math.max(0, breakMinutes - STANDARD_BREAK_MINUTES);

}


function isSameDay(firstDate, secondDate) {
    return firstDate.getFullYear() === secondDate.getFullYear() &&
        firstDate.getMonth() === secondDate.getMonth() &&
        firstDate.getDate() === secondDate.getDate();
}


function isSameWeek(date, referenceDate) {

    const start = new Date(referenceDate);
    const day = start.getDay();
    start.setDate(start.getDate() - day);
    start.setHours(0, 0, 0, 0);

    const end = new Date(start);
    end.setDate(end.getDate() + 7);

    return date >= start && date < end;

}


function formatReportHours(minutes) {
    const hours = Math.floor(minutes / 60);
    const remainingMinutes = minutes % 60;
    return `${hours}h ${remainingMinutes}m`;
}


function formatReportOverbreak(minutes) {
    return minutes > 0 ? `${formatReportHours(minutes)} over` : "None";
}


function formatCurrency(amount) {
    return `₱${amount.toLocaleString("en-PH", {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
    })}`;
}


// ------------------------------------------
// Load Leave Requests
// ------------------------------------------

async function loadLeaveRequests() {

    const tableBody = document.getElementById("leaveRequestsTableBody");

    if (!tableBody) {
        return;
    }

    tableBody.innerHTML = `
        <tr>
            <td colspan="7">Loading leave requests...</td>
        </tr>
    `;

    try {

        const {
            data: requests,
            error
        } = await supabaseClient
            .from("leave_requests")
            .select("id, user_id, leave_type, start_date, end_date, reason, status, created_at")
            .order("created_at", { ascending: false });

        if (error) {
            throw error;
        }

        const leaveRequests = requests || [];
        const userIds = leaveRequests.map(function (request) {
            return request.user_id;
        });
        let profiles = [];

        if (userIds.length > 0) {
            const {
                data: employeeProfiles,
                error: profilesError
            } = await supabaseClient
                .from("profiles")
                .select("id, full_name, employee_number")
                .eq("role", "employee")
                .in("id", userIds);

            if (profilesError) {
                throw profilesError;
            }

            profiles = employeeProfiles || [];
        }

        const profilesById = new Map(profiles.map(function (profile) {
            return [profile.id, profile];
        }));

        loadedLeaveRequests = sortLeaveRequests(leaveRequests.map(function (request) {
                return {
                    ...request,
                    profile: profilesById.get(request.user_id)
                };
            }));

        renderLeaveRequests(loadedLeaveRequests, tableBody);

    } catch (error) {

        console.error("Leave request loading error:", error);
        tableBody.innerHTML = `
            <tr>
                <td colspan="7">Unable to load leave requests right now.</td>
            </tr>
        `;

    }

}


function sortLeaveRequests(requests) {
    return requests.slice().sort(function (first, second) {
        const firstStatus = String(first.status || "").toLowerCase();
        const secondStatus = String(second.status || "").toLowerCase();
        const statusDifference =
            (LEAVE_STATUS_ORDER[firstStatus] ?? 3) -
            (LEAVE_STATUS_ORDER[secondStatus] ?? 3);

        if (statusDifference !== 0) return statusDifference;

        const firstCreatedAt = Date.parse(first.created_at) || 0;
        const secondCreatedAt = Date.parse(second.created_at) || 0;
        return secondCreatedAt - firstCreatedAt;
    });
}


function renderLeaveRequests(requests, tableBody) {

    if (requests.length === 0) {
        tableBody.innerHTML = `
            <tr>
                <td colspan="7">No leave requests submitted yet.</td>
            </tr>
        `;

        return;
    }

    tableBody.innerHTML = requests.map(function (request) {
        const profile = request.profile || {};

        return `
            <tr>
                <td>${escapeHtml(profile.full_name || "—")}</td>
                <td>${escapeHtml(profile.employee_number || "—")}</td>
                <td>${escapeHtml(formatLeaveDate(request.start_date))}</td>
                <td>${escapeHtml(formatLeaveDate(request.end_date))}</td>
                <td><button type="button" class="details-button" data-leave-details="${escapeHtml(request.id)}">Details</button></td>
                <td>${escapeHtml(formatLeaveDateTime(request.created_at))}</td>
                <td>${renderLeaveStatus(request)}</td>
            </tr>
        `;
    }).join("");

}


function renderLeaveStatus(request) {

    if (request.status !== "pending") {
        return `<span class="leave-status ${escapeHtml(request.status)}">${escapeHtml(request.status)}</span>`;
    }

    return `
        <div class="leave-status-menu">
            <button type="button" class="leave-status pending" data-toggle-leave-status="${escapeHtml(request.id)}">Pending</button>
            <div class="leave-status-options" data-leave-options="${escapeHtml(request.id)}" hidden>
                <button type="button" class="approve-button" data-leave-id="${escapeHtml(request.id)}" data-leave-status="approved">Approve</button>
                <button type="button" class="reject-button" data-leave-id="${escapeHtml(request.id)}" data-leave-status="rejected">Reject</button>
            </div>
        </div>
    `;

}


function openLeaveDetails(request) {

    document.getElementById("leaveModalType").textContent = request.leave_type || "—";
    document.getElementById("leaveModalReason").textContent = request.reason || "—";
    document.getElementById("leaveDetailsModal").hidden = false;

}


function closeLeaveDetails() {
    document.getElementById("leaveDetailsModal").hidden = true;
}


async function reviewLeaveRequest(requestId, status) {

    const { error } = await supabaseClient.rpc("review_leave_request", {
        request_id: Number(requestId),
        decision: status
    });

    if (error) {
        console.error("Leave request update error:", error);
        alert("Unable to update this leave request.");
        return;
    }

    alert(`Leave request ${status}.`);
    await loadLeaveRequests();

}


function setupLeaveRequestActions() {

    const tableBody = document.getElementById("leaveRequestsTableBody");

    if (!tableBody) {
        return;
    }

    tableBody.addEventListener("click", function (event) {
        const detailsButton = event.target.closest("button[data-leave-details]");
        const statusButton = event.target.closest("button[data-toggle-leave-status]");
        const button = event.target.closest("button[data-leave-id]");

        if (detailsButton) {
            const request = loadedLeaveRequests.find(function (item) {
                return String(item.id) === detailsButton.dataset.leaveDetails;
            });

            if (request) {
                openLeaveDetails(request);
            }

            return;
        }

        if (statusButton) {
            const options = tableBody.querySelector(
                `[data-leave-options="${statusButton.dataset.toggleLeaveStatus}"]`
            );
            if (options) options.hidden = !options.hidden;
            return;
        }

        if (!button) {
            return;
        }

        reviewLeaveRequest(
            button.dataset.leaveId,
            button.dataset.leaveStatus
        );
    });

    document.querySelectorAll("[data-close-leave-modal]").forEach(function (element) {
        element.addEventListener("click", closeLeaveDetails);
    });

}


function formatLeaveDate(value) {

    if (!value) {
        return "—";
    }

    const date = new Date(`${value}T00:00:00`);

    if (Number.isNaN(date.getTime())) {
        return "—";
    }

    return date.toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
        year: "numeric"
    });

}


function formatLeaveDateTime(value) {

    if (!value) {
        return "—";
    }

    const date = new Date(value);

    if (Number.isNaN(date.getTime())) {
        return "—";
    }

    return date.toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
        year: "numeric"
    });

}


// ------------------------------------------
// Load Attendance
// ------------------------------------------

async function loadAttendance() {

    const tableBody = document.getElementById("attendanceTableBody");

    if (!tableBody) {
        return;
    }

    tableBody.innerHTML = `
        <tr>
            <td colspan="10">Loading attendance...</td>
        </tr>
    `;

    try {

        let { data: attendance, error: attendanceError } = await supabaseClient
            .from("attendance")
            .select(`
                id,
                user_id,
                date,
                time_in,
                break_in,
                break_out,
                time_out,
                shift_type,
                pay_type,
                overtime_in,
                overtime_out,
                overtime_pay_type
            `)
            .order("date", { ascending: false });


        if (attendanceError && isMissingQrAttendanceSchema(attendanceError)) {
            const legacyAttendanceResult = await supabaseClient
                .from("attendance")
                .select("id, user_id, date, time_in, break_in, break_out, time_out")
                .order("date", { ascending: false });
            if (legacyAttendanceResult.error) throw legacyAttendanceResult.error;
            attendance = legacyAttendanceResult.data;
            setQrAttendanceSchemaStatus(false);
        } else if (attendanceError) {
            throw attendanceError;
        } else {
            setQrAttendanceSchemaStatus(true);
        }


        const attendanceRecords = attendance || [];
        const userIds = attendanceRecords.map(function (record) {
            return record.user_id;
        });
        let profiles = [];

        if (userIds.length > 0) {
            const {
                data: employeeProfiles,
                error: profilesError
            } = await supabaseClient
                .from("profiles")
                .select("id, full_name, employee_number, email")
                .eq("role", "employee")
                .in("id", userIds);

            if (profilesError) {
                throw profilesError;
            }

            profiles = employeeProfiles || [];
        }

        const profilesById = new Map(profiles.map(function (profile) {
            return [profile.id, profile];
        }));

        const employeeAttendance = attendanceRecords
            .filter(function (record) {
                return profilesById.has(record.user_id);
            })
            .map(function (record) {
                return {
                    ...record,
                    profile: profilesById.get(record.user_id)
                };
            });

        renderAttendance(employeeAttendance, tableBody);

    } catch (error) {

        console.error("Attendance loading error:", error);
        tableBody.innerHTML = `
            <tr>
                <td colspan="10">Unable to load attendance records right now.</td>
            </tr>
        `;

    }

}


function renderAttendance(records, tableBody) {

    if (records.length === 0) {
        tableBody.innerHTML = `
            <tr>
                <td colspan="10">No attendance records found.</td>
            </tr>
        `;

        return;
    }

    tableBody.innerHTML = records.map(function (record) {
        const profile = record.profile;

        return `
            <tr>
                <td>${escapeHtml(profile?.full_name || "—")}</td>
                <td>${escapeHtml(profile?.employee_number || "—")}</td>
                <td>${escapeHtml(formatAttendanceDate(record.date))}</td>
                <td>
                    ${record.shift_type == null ? `<small class="attendance-pay-details">QR migration pending</small>` : `
                    <span class="pay-mode-badge ${record.pay_type === "double" ? "double" : "normal"}">${record.pay_type === "double" ? "Double pay" : "Regular pay"}</span>
                    <small class="attendance-pay-details">${record.shift_type === "night" ? "Night shift" : "Day shift"}</small>
                    `}
                </td>
                <td>${escapeHtml(formatAttendanceTime(record.time_in))}</td>
                <td>${escapeHtml(formatAttendanceTime(record.break_in))}</td>
                <td>${escapeHtml(formatAttendanceTime(record.break_out))}</td>
                <td>${escapeHtml(formatAttendanceTime(record.time_out))}</td>
                <td>
                    ${escapeHtml(formatAttendanceTime(record.overtime_in))}
                    ${qrAttendanceSchemaAvailable && record.overtime_in ? `<small class="attendance-pay-details">${record.overtime_pay_type === "double" ? "Double-rate OT" : "Regular-rate OT"}</small>` : ""}
                </td>
                <td>${escapeHtml(formatAttendanceTime(record.overtime_out))}</td>
            </tr>
        `;
    }).join("");

}


function formatAttendanceDate(value) {

    if (!value) {
        return "—";
    }

    const parts = value.split("-").map(Number);
    const date = parts.length === 3
        ? new Date(parts[0], parts[1] - 1, parts[2])
        : new Date(value);

    if (Number.isNaN(date.getTime())) {
        return "—";
    }

    return date.toLocaleDateString("en-US", {
        month: "long",
        day: "numeric",
        year: "numeric"
    });

}


function formatAttendanceTime(value) {

    if (!value) {
        return "—";
    }

    const date = new Date(value);

    if (Number.isNaN(date.getTime())) {
        return "—";
    }

    return date.toLocaleTimeString("en-US", {
        hour: "2-digit",
        minute: "2-digit",
        hour12: true
    });

}


function setupSectionNavigation() {

    document.querySelectorAll(".nav-link").forEach(function (link) {
        link.addEventListener("click", function () {
            showSection(link.dataset.section);
        });
    });

}


// ------------------------------------------
// Load Employees
// ------------------------------------------

async function loadEmployees() {

    const tableBody = document.getElementById("employeeTableBody");

    try {

        const {
            data: employees,
            error
        } = await supabaseClient
            .from("profiles")
            .select("id, full_name, employee_number, email, role")
            .eq("role", "employee")
            .order("full_name", { ascending: true });


        if (error) {
            throw error;
        }


        const employeeList = sortEmployeesAlphabetically(employees || []);

        updateEmployeeCount(employeeList.length);
        renderEmployees(employeeList, tableBody);

    } catch (error) {

        console.error("Employee loading error:", error);
        updateEmployeeCount(0);

        if (tableBody) {
            tableBody.innerHTML = `
                <tr>
                    <td colspan="4">Unable to load employees right now.</td>
                </tr>
            `;
        }

    }

}


function sortEmployeesAlphabetically(employees) {
    return employees.slice().sort(function (first, second) {
        return EMPLOYEE_NAME_COLLATOR.compare(
            first.full_name || "",
            second.full_name || ""
        );
    });
}


function updateEmployeeCount(count) {

    const employeeCount = document.getElementById("employeeCount");
    const totalEmployees = document.getElementById("totalEmployees");

    if (employeeCount) {
        employeeCount.textContent = count;
    }

    if (totalEmployees) {
        totalEmployees.textContent = count;
    }

}


function renderEmployees(employees, tableBody) {

    if (!tableBody) {
        return;
    }

    if (employees.length === 0) {
        tableBody.innerHTML = `
            <tr>
                <td colspan="4">No employees registered yet.</td>
            </tr>
        `;

        return;
    }

    tableBody.innerHTML = employees.map(function (employee) {
        return `
            <tr>
                <td>${escapeHtml(employee.full_name || "-")}</td>
                <td>${escapeHtml(employee.employee_number || "-")}</td>
                <td>${escapeHtml(employee.email || "-")}</td>
                <td>${escapeHtml(employee.role || "employee")}</td>
            </tr>
        `;
    }).join("");

}


function escapeHtml(value) {

    return String(value)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");

}


// ------------------------------------------
// Start Dashboard
// ------------------------------------------

if (
    window.location.pathname.endsWith(
        "dashboard.html"
    )
) {

    setupSectionNavigation();
    setupAttendanceQrGenerator();
    setupLeaveRequestActions();
    loadDashboard();

}
