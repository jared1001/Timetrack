// ==========================================
// TimeTrack Manager - Employees
// ==========================================

async function loadEmployees() {

    const table =
        document.getElementById(
            "employeeTable"
        );


    if (!table) {
        return;
    }


    try {

        const {
            data: employees,
            error
        } = await supabaseClient
            .from("profiles")
            .select(
                "full_name, employee_number, email, role"
            )
            .eq("role", "employee")
            .order(
                "full_name",
                {
                    ascending: true
                }
            );


        if (error) {
            throw error;
        }


        table.innerHTML = "";


        if (
            !employees ||
            employees.length === 0
        ) {

            table.innerHTML = `
                <tr>
                    <td colspan="4">
                        No employees found.
                    </td>
                </tr>
            `;

            return;

        }


        employees.forEach(
            function (employee) {

                const row =
                    document.createElement("tr");


                row.innerHTML = `

                    <td>
                        ${escapeHtml(
                            employee.full_name || "-"
                        )}
                    </td>

                    <td>
                        ${escapeHtml(
                            employee.employee_number || "-"
                        )}
                    </td>

                    <td>
                        ${escapeHtml(
                            employee.email || "-"
                        )}
                    </td>

                    <td>
                        ${escapeHtml(
                            employee.role || "employee"
                        )}
                    </td>

                `;


                table.appendChild(row);

            }
        );


    } catch (error) {

        console.error(
            "Employee loading error:",
            error
        );


        table.innerHTML = `
            <tr>
                <td colspan="4">
                    Unable to load employees.
                </td>
            </tr>
        `;

    }

}


// ------------------------------------------
// Basic HTML escaping
// ------------------------------------------

function escapeHtml(value) {

    return String(value)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");

}

