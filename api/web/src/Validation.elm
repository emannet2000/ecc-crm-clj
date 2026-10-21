module Validation exposing (feature, passwordError)

import Char
import Date
import Dict exposing (Dict)


passwordError : String -> String
passwordError value =
    let
        bytes = String.toList value |> List.map (\c -> let n = Char.toCode c in if n < 128 then 1 else if n < 2048 then 2 else if n < 65536 then 3 else 4) |> List.sum
    in
    if String.length value < 12 then "Use at least 12 characters."
    else if bytes > 72 then "Use a password no longer than 72 UTF-8 bytes."
    else ""


feature : String -> String -> String -> Dict String String -> Dict String String
feature section action inlineOwner values =
    let
        get key = Dict.get key values |> Maybe.withDefault "" |> String.trim
        required key label = if get key == "" then Just (key, label ++ " is required.") else Nothing
        selected key = required key "Select an item first"
        owner = if inlineOwner == "" then required "owner" "Record" else Nothing
        date key = if get key == "" then Nothing else case Date.fromIsoString (get key) of
            Ok _ -> Nothing
            Err _ -> Just (key, "Enter a valid date.")
        integer key low high =
            if get key == "" then Nothing else case String.toInt (get key) of
                Just n -> if n >= low && n <= high then Nothing else Just (key, "Use a whole number from " ++ String.fromInt low ++ " to " ++ String.fromInt high ++ ".")
                Nothing -> Just (key, "Enter a whole number.")
        range = [date "from", date "to", if (get "from" == "") /= (get "to" == "") then Just (if get "from" == "" then "from" else "to", "Choose both dates, or clear both to use the default range.") else Nothing, if get "from" /= "" && get "to" /= "" && get "from" > get "to" then Just ("to", "End date must be on or after the start date.") else Nothing]
        checks =
            if action == "range" then range else
            case (section, action) of
                ("tasks", "save") -> [selected "id", required "title" "Title", required "assignee" "Staff member", date "dueDate", integer "recurrenceDays" 1 366, if get "recurrenceDays" /= "" then required "dueDate" "A deadline for repeating tasks" else Nothing]
                ("tasks", "create") -> [owner, required "title" "Title", required "assignee" "Staff member", date "dueDate", integer "recurrenceDays" 1 366, if get "recurrenceDays" /= "" then required "dueDate" "A deadline for repeating tasks" else Nothing]
                ("applications", "checklist") -> [selected "id", required "template" "Checklist template"]
                ("applications", _) -> [owner, required "category" "Application type", required "destination" "Destination", required "stage" "Stage", date "intakeDate", date "deadline"]
                ("checklist-templates", _) -> [required "name" "Checklist name", if get "requiredDocuments" == "" && get "optionalDocuments" == "" then Just("requiredDocuments","Add at least one document requirement.") else Nothing]
                ("milestones", _) -> [owner, required "kind" "Milestone type", required "title" "Milestone", date "plannedOn", date "completedOn", if get "status" == "Completed" then required "completedOn" "Completion date" else Nothing]
                ("contact-log", _) -> [owner, required "channel" "Channel", required "direction" "Direction", required "outcome" "Outcome", required "occurredOn" "Interaction date", date "occurredOn", required "note" "Conversation summary"]
                ("history", _) -> [owner, required "note" "Note"]
                ("documents", "save") -> [owner, required "title" "Document title", date "expiresOn", if get "status" == "Rejected" then required "reviewNote" "Feedback explaining the rejection" else Nothing]
                ("documents", _) -> [selected "id", if action == "attach" then required "document" "File" else Nothing]
                ("reminders", _) -> [required "task" "Task", integer "daysBefore" 0 365, integer "escalateAfter" 1 365]
                ("appointments", _) -> [owner, required "title" "Appointment title", required "assignee" "Staff member", required "startsAt" "Start time", required "endsAt" "End time", if get "startsAt" /= "" && get "endsAt" <= get "startsAt" then Just ("endsAt", "End time must be after the start time.") else Nothing]
                ("communication", _) -> [owner, required "subject" "Subject", required "message" "Message"]
                ("portal", "create") -> [owner, integer "days" 1 30]
                ("portal", "grant") -> [selected "id", required "document" "Approved file"]
                ("portal", _) -> [selected "id"]
                ("mail", _) -> [selected "id"]
                ("merge", _) -> [required "source" "Source record", required "target" "Surviving record", if get "source" /= "" && get "source" == get "target" then Just ("target", "Choose two different records.") else Nothing, if action == "confirm" && get "confirmation" /= "MERGE" then Just ("confirmation", "Type MERGE after reviewing the preview.") else Nothing]
                ("payment-history", "reverse") -> [selected "id",required "payment" "Receipt",required "paidOn" "Reversal date",date "paidOn",required "reason" "Reason"]
                ("periods", _) -> [required "month" "Financial month",required "reason" "Reason"]
                ("reconciliation", "import") -> [required "account" "Bank account",required "currency" "Currency",required "csv" "Statement CSV"]
                ("reconciliation", "match") -> [selected "id",required "match" "Matching recorded entry",required "reason" "Reason"]
                ("reconciliation", _) -> [selected "id",required "reason" "Reason"]
                ("payments", "record") -> [selected "id", required "amount" "Payment amount", required "paidOn" "Payment date", date "paidOn", required "method" "Payment method"]
                ("payments", "reverse") -> [selected "id", required "payment" "Receipt", required "paidOn" "Reversal date", date "paidOn", required "reason" "Reason"]
                ("expenses", "submit") -> [required "supplier" "Supplier",required "description" "Description",required "category" "Category",required "amount" "Amount",required "expenseOn" "Expense date",date "expenseOn"]
                ("expenses", "pay") -> [selected "id",required "paidOn" "Payment date",date "paidOn",required "method" "Payment method"]
                ("expenses", "reverse-expense") -> [selected "id",required "paidOn" "Reversal date",date "paidOn",required "reason" "Reason"]
                ("expenses", "reject") -> [selected "id",required "reason" "Reason"]
                ("expenses", "approve") -> [selected "id"]
                ("invoices", "send") -> [selected "id"]
                ("invoices", _) -> [owner, required "description" "Description", required "amount" "Amount", if Maybe.withDefault 0 (String.toFloat (get "amount")) <= 0 then Just ("amount", "Enter an amount greater than zero.") else Nothing, required "dueDate" "Due date", date "dueDate"]
                ("search", "save") -> [required "name" "View name"]
                ("search", "views") -> []
                ("search", _) -> [selected "id"]
                ("security", "access") -> [required "user" "Team account", required "password" "Your current password", required "accessLevel" "Record access"]
                ("security", "reset-mfa") -> [required "user" "Team account", required "password" "Your current password", required "code" "Your authenticator or recovery code", required "reason" "Recovery reason"]
                ("security", "revoke-user") -> [required "user" "Team account"]
                ("security", "suspend") -> [required "user" "Team account"]
                ("security", "resume") -> [required "user" "Team account"]
                ("security", "revoke") -> [selected "session"]
                ("security", _) -> [required "password" "Current password", if action /= "setup" then required "code" "Authenticator or recovery code" else Nothing]
                ("notifications", "read") -> [selected "id"]
                _ -> []
    in
    List.filterMap identity checks |> Dict.fromList
