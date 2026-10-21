module Features exposing (view, embedded, conflictView, formValues, portalView, rowForm, defaults)

import Char
import Dict exposing (Dict)
import File
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput)
import Json.Decode as D
import State exposing (..)
import Ui

str : String -> D.Value -> String
str key item = D.decodeValue (D.field key scalar) item |> Result.withDefault ""

scalar : D.Decoder String
scalar = D.oneOf [ D.string, D.map String.fromInt D.int, D.map String.fromFloat D.float, D.map (\b -> if b then "true" else "false") D.bool, D.null "" ]

items : String -> D.Value -> List D.Value
items key item = D.decodeValue (D.field key (D.list D.value)) item |> Result.withDefault []

formValues : D.Value -> Dict String String
formValues row =
    D.decodeValue (D.keyValuePairs D.value) row |> Result.withDefault []
        |> List.filterMap (\(key,value) -> D.decodeValue scalar value |> Result.toMaybe |> Maybe.map (Tuple.pair key))
        |> Dict.fromList
        |> Dict.map (\key value_ -> if List.member key ["required","enabled","assignments","deadlines","documents","escalations","emailEnabled"] then (if value_=="1" then "true" else if value_=="0" then "false" else value_) else value_)

rowForm : D.Value -> Dict String String
rowForm row =
    let
        values = formValues row
        rid = str "id" row
    in
    values |> Dict.insert "expectedRevision" (str "revision" row) |> Dict.insert "request" ("request:" ++ rid) |> Dict.insert "session" rid |> Dict.insert "user" rid


defaults : String -> Dict String String
defaults section = Dict.fromList
    [ ("status", case section of
        "documents" -> "Missing"
        "appointments" -> "Scheduled"
        "invoices" -> "Draft"
        _ -> "Pending")
    , ("required","true"), ("enabled","true"), ("priority","Medium")
    , ("entity", if section == "merge" then "leads" else "tasks"), ("currency","PHP"), ("daysBefore","1"), ("escalateAfter","2"), ("days","7")
    , ("mine","true"), ("overdue","false"), ("assignments","true"), ("deadlines","true"), ("documents","true"), ("escalations","true"), ("emailEnabled","true")
    ]

-- Fields carry labels and control types; internal API field names are never displayed.
type alias Field = ( String, String, String )

fields : String -> List Field
fields section = case section of
    "tasks" -> [("Title","title","text"),("Description","description","textarea"),("Due date","dueDate","date"),("Priority","priority","Low|Medium|High|Urgent"),("Status","status","Pending|In Progress|Done"),("Assigned to","assignee","staff"),("Repeat every (days; blank for one time)","recurrenceDays","number")]
    "history" -> [("Record","owner","record"),("Note or conversation summary","note","textarea")]
    "documents" -> [("Record","owner","record"),("Required document","title","text"),("Required?","required","true|false"),("Review status","status","Missing|Received|Approved|Rejected"),("Expires on","expiresOn","date"),("Feedback for the client","reviewNote","textarea"),("Existing file to attach as a new version","document","document")]
    "reminders" -> [("Task","task","task"),("Days before deadline","daysBefore","number"),("Escalate to administrators after overdue days","escalateAfter","number"),("Email reminders enabled?","enabled","true|false")]
    "merge" -> [("Record type","entity","leads|clients"),("Source to archive","source","merge"),("Surviving record","target","merge"),("Type MERGE after reviewing the preview","confirmation","text")]
    "reports" -> [("From date","from","date"),("To date","to","date")]
    "search" -> [("View name","name","text"),("Records","entity","leads|clients|tasks|cases"),("Contains","query","text"),("Assigned to me?","mine","true|false"),("Overdue only?","overdue","true|false")]
    "security" -> [("Current password","password","password"),("Authenticator or recovery code","code","text")]
    "appointments" -> [("Record","owner","record"),("Appointment","title","text"),("Staff member","assignee","staff"),("Starts (UTC)","startsAt","datetime-local"),("Ends (UTC)","endsAt","datetime-local"),("Location or meeting link","location","text"),("Status","status","Scheduled|Completed|Cancelled")]
    "invoices" -> [("Client","owner","client"),("Description","description","textarea"),("Currency","currency","PHP|USD|EUR|GBP|AUD|CAD|NZD"),("Amount","amount","text"),("Due date","dueDate","date"),("Status","status","Draft|Issued|Paid|Void")]
    "portal" -> [("Client","owner","client"),("Access duration (days)","days","number"),("Approved file to share","document","document")]
    "notifications" -> [("Task assignments","assignments","true|false"),("Upcoming deadlines","deadlines","true|false"),("Document rejections","documents","true|false"),("Overdue escalation","escalations","true|false"),("Reminder emails","emailEnabled","true|false")]
    "mail" -> []
    "ageing" -> [("Created from","from","date"),("Created to","to","date")]
    "bottlenecks" -> [("Created from","from","date"),("Created to","to","date")]
    "trends" -> [("From","from","date"),("To","to","date")]
    "communication" -> [("Contact record","owner","record"),("Subject","subject","text"),("Message","message","textarea")]
    _ -> []

heading : String -> (String,String)
heading section = case section of
    "tasks" -> ("Edit and assign tasks","Select a task below to edit its deadline, owner and recurrence. A completed recurring task creates its next occurrence automatically.")
    "history" -> ("Client and case history","Keep conversations, decisions and next steps together. Notes are attributed to their author.")
    "documents" -> ("Document checklist and review","Create requirements, upload directly into an item, and record approval or feedback once scanning succeeds.")
    "reminders" -> ("Email reminders and escalation","Send deadline reminders to the assigned staff member and escalate overdue work to administrators.")
    "merge" -> ("Merge duplicate records","Preview both records before confirming. Children are preserved; the source is archived and its original fields remain available in the audit trail.")
    "reports" -> ("Management reports","Choose a date range. Lead conversions use the cohort created in that range; workload and overdue counts show the current position.")
    "search" -> ("Search and saved views","Search contacts, phone numbers, tasks and cases. Save personal views for work such as your overdue cases.")
    "security" -> ("Account security","Set up a SHA-256 compatible authenticator, keep recovery codes offline, and review or revoke active sessions.")
    "appointments" -> ("Appointments and calendar","Schedule appointments in UTC. Overlapping appointments for the same staff member are prevented.")
    "invoices" -> ("Invoices","Create drafts, issue invoices and record payment manually. Issued amounts are locked; no online payment is taken.")
    "portal" -> ("Client portal access","Create a private, one-use sign-in link. Only explicitly shared, approved files become downloadable by the client.")
    "notifications" -> ("Notification centre","Review assignments, deadlines, document rejections and overdue work. Preferences hide selected categories and control reminder emails.")
    "mail" -> ("Email delivery","Track queue status and failures. Accepted by SMTP means the mail server accepted the message; inbox delivery is not confirmed.")
    "ageing" -> ("Case ageing","Review open cases, their age and overdue deadlines. Exports contain up to 10,000 rows; narrow the date range for larger datasets.")
    "bottlenecks" -> ("Case bottlenecks","Cases grouped by stage, with time in the current stage. Legacy cases without stage history use their creation date.")
    "trends" -> ("Historical workload","Daily snapshots begin when the scheduler is enabled. Today updates during the day; previous days retain their last recorded workload.")
    "communication" -> ("Email a contact","Send through the configured mail service. Delivery is queued and the conversation is recorded in the shared history.")
    _ -> ("Workspace","")

view : Model -> String -> Html Msg
view model section =
    let
        (title,description) = heading section
        get key = Dict.get key model.featureForm |> Maybe.withDefault ""
        options = items "options" model.featureData
        isViewer = Maybe.map .role model.user == Just "viewer"
        canWrite = not isViewer || List.member section ["security","search","notifications"]
        control (labelText,key,kind) =
            let
                selectedValue = get key
                choices = if String.contains "|" kind then String.split "|" kind |> List.map (\v -> (v, if v == "true" then "Yes" else if v == "false" then "No" else v)) else
                    options |> List.filter (\item -> let v=str "value" item in case kind of
                        "record" -> List.any (\prefix -> String.startsWith prefix v) ["lead:","client:","case:"]
                        "merge" -> String.startsWith (if get "entity" == "clients" then "client:" else "lead:") v
                        _ -> String.startsWith (kind ++ ":") v)
                    |> List.map (\item -> let v=str "value" item in (if List.member key ["assignee","task","source","target"] then String.split ":" v |> List.reverse |> List.head |> Maybe.withDefault v else v,str "label" item))
                attrs = [ class "input", value selectedValue, onInput (FeatureField key), id ("work-" ++ key), attribute "aria-describedby" "feature-error" ]
            in
            div [ class "form-group" ]
                [ label [ for ("work-" ++ key) ] [ text labelText ]
                , if kind == "textarea" then textarea (attrs ++ [rows 4]) []
                  else if List.member kind ["record","staff","task","client","document","merge"] || String.contains "|" kind then select attrs
                    (option [value ""] [text "Choose…"] :: List.map (\(v,l) -> option [value v,selected (v==selectedValue)] [text l]) choices)
                  else input (attrs ++ [ type_ kind ]) []
                ]
        action name labelText = button [class "btn btn-primary",disabled (not canWrite || model.featureBusy),onClick (if List.member name ["confirm","suspend","revoke-user","grant","revoke","retry"] then ConfirmRequested ("Confirm: " ++ labelText ++ "?") (FeatureRun name) else FeatureRun name)] [text labelText]
        actions = case section of
            "tasks" -> (if model.inlineOwner/="" then [action "create" "Create task here"] else []) ++ [action "save" "Save selected task"]
            "history" -> [action "add" "Add note"]
            "merge" -> [action "preview" "Preview merge",action "confirm" "Confirm merge"]
            "reports" -> [action "range" "Update report"]
            "ageing" -> [action "range" "Update report"]
            "bottlenecks" -> [action "range" "Update report"]
            "trends" -> [action "range" "Update report"]
            "mail" -> if Maybe.map .role model.user==Just "admin" then [action "retry" "Retry selected failed message"] else []
            "notifications" -> [action "preferences" "Save notification preferences",action "read" "Mark selected notification read"]
            "search" -> [action "save" "Save personal view",action "views" "Show saved views",action "apply" "Open selected view",action "delete" "Delete selected view"]
            "security" -> [action "setup" "Start authenticator setup",action "enable" "Enable MFA",action "disable" "Disable MFA",action "revoke" "Revoke selected session"]
            "documents" -> [action "save" "Save checklist item"] ++ (if model.inlineOwner=="" then [action "attach" "Attach selected file as a new version"] else []) ++ (if Maybe.map .role model.user==Just "admin" then [action "rescan" "Retry failed scan for selected item"] else [])
            "portal" -> [action "create" "Create private sign-in link",action "grant" "Share selected approved file",action "revoke" "Revoke selected link"]
            "communication" -> [action "send" "Queue email"]
            "invoices" -> [action "save" "Save invoice",action "send" "Email selected invoice"]
            _ -> [action "save" "Save changes"]
        row item = div [class "operation-row"]
            [ div []
                [ h3 [] [text (str "title" item)]
                , if section=="reports" then reportRow item else p [] [text (String.join " · " (List.filter ((/=) "") (List.map (\key -> let v=str key item in if v=="" then "" else fieldLabel key ++ ": " ++ v) (columns section))))]
                , if str "path" item /= "" then a [class "btn btn-outline",href (str "path" item)] [text "Open record"] else text ""
                , div [] (List.map (\file -> if str "scanStatus" file=="Clean" then a [class "btn btn-outline",href ("/api/documents/" ++ str "documentId" file ++ "/download")] [text ("Version " ++ str "version" file ++ " · " ++ str "filename" file)] else p [] [text ("Version " ++ str "version" file ++ " · " ++ str "filename" file ++ " · " ++ str "scanStatus" file)]) (items "versions" item))
                , if section=="documents" then button [class "btn btn-outline",disabled (not canWrite || model.featureBusy || model.checklistFile==Nothing),onClick (ChecklistUpload (String.toInt(str "id" item) |> Maybe.withDefault 0) (String.toInt(str "revision" item) |> Maybe.withDefault 0))] [text "Upload selected file to this requirement"] else text ""
                ]
            , if List.member section ["history","reports","communication","ageing","bottlenecks","trends"] then text "" else button [class "btn btn-outline",disabled model.featureBusy,onClick (FeatureEdit item)] [text (if section=="search" then "Select view" else "Select / edit")]
            ]
        extraUsers = D.decodeValue (D.at ["security","users"] (D.list D.value)) model.featureData |> Result.withDefault []
    in
    div []
        [ div [class "page-head"] [div [] [h2 [] [text title],p [class "page-description"] [text description]]]
        , if section=="appointments" then a [class "btn btn-outline",href "/api/workspace/calendar.ics"] [text "Download calendar (.ics)"] else text ""
        , if section=="security" then p [] [text (if D.decodeValue (D.at ["security","enabled"] D.bool) model.featureData == Ok True then "Authenticator protection is enabled." else "Authenticator protection is not enabled. Administrators may be required to set it up before opening records.")] else text ""
        , if not (List.member section ["security","reports"]) then div [class "form-group"] [label [for "feature-search"] [text "Search this list and record choices"],input [id "feature-search",class "input",value model.featureSearch,onInput FeatureSearch,placeholder "Name, phone, task, case or file…"] []] else text ""
        , div [class "card"] (List.map control (fields section |> List.filter (\(_,key,_) -> model.inlineOwner=="" || key/="document")) ++ [div [class "form-actions"] (actions ++ [button [class "btn btn-outline",onClick FeatureReset] [text "New / clear form"]])])
        , if model.featureError/="" then p [id "feature-error",class "error-banner",attribute "role" "alert"] [text model.featureError] else span [id "feature-error"] []
        , if section=="documents" then div [class "card"]
            [ label [for "checklist-file"] [text "Upload directly into a checklist item (up to 25 MB)"]
            , input [id "checklist-file",type_ "file",Html.Events.on "change" (D.map ChecklistFile (D.at ["target","files"] (D.index 0 File.decoder)))] []
            , p [] [text "Choose a file, then use the upload button on its requirement. Files remain quarantined until scanning succeeds."]
            , div [class "form-actions"] (List.map (\(filter,labelText) -> button [class "btn btn-outline",onClick(FeatureSearch filter)] [text labelText]) [("review","Review queue"),("expiring","Expiring documents"),("outstanding","Outstanding requirements"),("","All documents")])
            , button [class "btn btn-outline",disabled model.featureBusy,onClick(PageStep 0)] [text "Refresh scan status"]
            ] else text ""
        , if section=="reports" then a [class "btn btn-outline",href ("/api/workspace/reports.csv?q=" ++ model.featureSearch)] [text "Export summary CSV"] else text ""
        , if section=="documents" then div [class "summary-strip"] (List.map (\summary -> p [] [text ("Required: " ++ str "required" summary ++ " · Outstanding: " ++ str "outstanding" summary ++ " · Awaiting review: " ++ str "review" summary ++ " · Expiring: " ++ str "expiring" summary)]) (items "summary" model.featureData)) else text ""
        , if List.member section ["ageing","bottlenecks","trends"] then a [class "btn btn-outline",href ("/api/workspace/report-export/" ++ section ++ "?q=" ++ model.featureSearch)] [text "Export CSV"] else text ""
        , resultView model.featureResult
        , if model.pageLoading then Ui.spinner else div [class "operations-list"] (List.map row model.opsData)
        , if section=="search" then div [] (List.map row (D.decodeValue (D.list D.value) model.featureResult |> Result.withDefault [])) else text ""
        , div [] (List.map row (items "results" model.featureResult))
        , if section=="security" then div [class "card"] (h3 [] [text "Team access"] :: List.map (\item -> div [class "operation-row"] [span [] [text (str "name" item ++ " · " ++ str "role" item ++ (if str "suspended" item=="1" then " · Suspended" else " · Active"))],button [class "btn btn-outline",disabled model.featureBusy,onClick (FeatureEdit item)] [text "Select account"]]) extraUsers ++ (if Maybe.map .role model.user==Just "admin" then [action "suspend" "Suspend selected account",action "resume" "Resume selected account",action "revoke-user" "Revoke selected account sessions"] else [])) else text ""
        ]

columns : String -> List String
columns section = case section of
    "tasks" -> ["recordName","assigneeName","status","priority","dueDate"]
    "history" -> ["actor","kind","date","note"]
    "documents" -> ["status","scanStatus","expiryWarning","expiresOn","reviewNote"]
    "mail" -> ["recipient","status","attempts","lastError","nextAttempt","sentAt"]
    "notifications" -> ["kind","status","date"]
    "ageing" -> ["stage","ageDays","overdueDays","staff"]
    "bottlenecks" -> ["cases","averageAgeDays","oldestDays"]
    "trends" -> ["date","openTasks","overdueTasks","openCases"]
    "reports" -> ["from","to","summary"]
    "security" -> ["created","expires"]
    "invoices" -> ["currency","amount","status","dueDate","description"]
    "appointments" -> ["startsAt","endsAt","location","status"]
    _ -> ["status","expires","kind","phone","email"]

resultView : D.Value -> Html Msg
resultView result =
    div [class "card",attribute "role" "status"]
        ([p [] [text (str "message" result)]]
        ++ List.filterMap (\key -> let value_=str key result in if value_=="" then Nothing else Just (div [] [strong [] [text (if key=="secret" then "Authenticator key: " else if key=="uri" then "Authenticator setup URI: " else "Private client sign-in link: ")],code [] [text value_]])) ["secret","uri","url"]
        ++ (if List.isEmpty (items "counts" result) then [] else List.map (\counts -> p [] [text (String.join " · " (List.map (\key -> key ++ ": " ++ str key counts) ["documents","tasks","cases","notes","activities","invoices"]))]) (items "counts" result))
        ++ (D.decodeValue (D.field "recoveryCodes" (D.list D.string)) result |> Result.withDefault [] |> List.map (\value_ -> p [] [code [] [text value_]])))

portalView : Model -> Html Msg
portalView model =
    let
        block name key render = div [class "card"] [h2 [] [text name],div [] (List.map render (items key model.portalData))]
    in
    div [class "container"]
        [ h1 [] [text "Your client workspace"]
        , p [] [text model.portalError]
        , button [class "btn btn-outline",onClick PortalLogout] [text "Sign out"]
        , block "Your details" "client" (\item -> p [] [text (str "name" item ++ " · " ++ str "number" item)])
        , block "Cases" "cases" (\item -> p [] [text (str "title" item ++ " · " ++ str "stage" item ++ " · " ++ str "deadline" item)])
        , div [class "form-group"] [label [for "portal-file"] [text "Choose a file to submit"],input [id "portal-file",type_ "file",Html.Events.on "change" (D.map PortalFile (D.at ["target","files"] (D.index 0 File.decoder)))] []]
        , block "Document checklist" "checklist" (\item -> div [class "operation-row"] [div [] [h3 [] [text (str "title" item)],p [] [text (str "status" item ++ " · " ++ str "feedback" item)]],button [class "btn btn-primary",disabled (model.portalFile==Nothing),onClick (PortalUpload (String.toInt (str "id" item) |> Maybe.withDefault 0))] [text "Submit selected file"]])
        , block "Shared documents" "documents" (\item -> a [class "btn btn-outline",href ("/api/portal/documents/" ++ str "id" item)] [text (str "title" item)])
        , block "Invoices" "invoices" (\item -> p [] [text ("INV-" ++ str "id" item ++ " · " ++ str "description" item ++ " · " ++ str "currency" item ++ " " ++ str "amount" item ++ " · " ++ str "status" item ++ " · Due " ++ str "dueDate" item)])
        ]

reportRow : D.Value -> Html Msg
reportRow item =
    let
        n key = D.decodeValue (D.field key D.float) item |> Result.withDefault 0
        percentage = if n "leads" == 0 then "0" else String.fromInt (round (100 * n "converted" / n "leads"))
    in
    div []
        (List.map (\(key,labelText) -> p [] [strong [] [text (labelText ++ ": ")],text (str key item)]) [("leads","Leads in cohort"),("converted","Converted leads"),("openTasks","Open tasks"),("overdueTasks","Overdue tasks"),("completedCases","Cases completed"),("averageCaseDays","Average case days")]
        ++ [p [] [text ("Conversion rate: " ++ percentage ++ "%")]])

embedded : Model -> Int -> Html Msg
embedded model cid =
    div [class "inline-workspace",attribute "aria-label" "Client and case work"]
        [ h2 [] [text "Work on this client or case"]
        , label [for "case-work-scope"] [text "Scope"]
        , select [id "case-work-scope",class "input",value model.inlineOwner,onInput InlineOwner]
            (option [value ("client:" ++ String.fromInt cid),selected (model.inlineOwner=="client:" ++ String.fromInt cid)] [text "Whole client"] ::
             (Maybe.map .cases model.clientDetail |> Maybe.withDefault [] |> List.map (\c -> option [value ("case:" ++ String.fromInt c.id),selected(model.inlineOwner=="case:" ++ String.fromInt c.id)] [text (Maybe.withDefault "Case" c.category ++ " · " ++ c.stage ++ " · " ++ String.fromInt c.id)])))
        , div [class "form-actions",attribute "aria-label" "Client work sections"] (List.map (\(section,labelText) -> button [class (if model.inlineSection==section then "btn btn-primary" else "btn btn-outline"),attribute "aria-pressed" (if model.inlineSection==section then "true" else "false"),onClick(InlineSection section)] [text labelText]) [("tasks","Edit tasks"),("history","Conversation history"),("documents","Document checklist")])
        , view model model.inlineSection
        , div [class "form-actions"]
            [button [class "btn btn-outline",disabled(model.pageOffset==0),onClick(PageStep -1)] [text "Previous work page"],button [class "btn btn-outline",disabled(List.length model.opsData<50),onClick(PageStep 1)] [text "Next work page"]]
        ]

conflictView : Model -> Html Msg
conflictView model =
    let
        latest = formValues model.conflictCurrent
        hidden key = List.member key ["id","revision","expectedRevision","request","session","user","password","uuPassword"]
        get values_ key = Dict.get key values_ |> Maybe.withDefault ""
        changed = Dict.keys latest |> List.filter (\key -> not(hidden key) && get model.conflictOriginal key /= get latest key)
        cell_ values_ key = td [] [text (get values_ key)]
        workflow = List.member model.conflictKind ["tasks","documents","reminders"]
    in
    if D.decodeValue (D.field "revision" D.int) model.conflictCurrent |> Result.toMaybe |> (==) Nothing then text "" else
    Ui.modal "Review changes before saving" (div []
        [ p [] [text "Your save was rejected because this record changed. Review the original, your draft and the latest version. Accepting a version does not submit the form."]
        , div [class "table-scroll"] [table [class "data-table"]
            [ caption [] [text "Fields changed since the form was opened"]
            , thead [] [tr [] (List.map (\labelText -> th [scope "col"] [text labelText]) ["Field","Original","Your draft","Latest","Action"])]
            , tbody [] (List.map (\key -> tr [] [th [scope "row"] [text (fieldLabel key)],cell_ model.conflictOriginal key,cell_ model.conflictEdits key,cell_ latest key,td [] [if workflow then button [class "btn btn-outline",onClick(ConflictUseCurrent key)] [text "Use latest value"] else text "Review in your form"]]) changed)
            ]]
        , p [] [text (if List.isEmpty changed then "The revision changed because related work changed. Your fields are unchanged in the latest version." else "Keeping your draft can replace the latest values for these fields.")]
        , button [class "btn btn-primary",onClick (ConfirmRequested "Use the latest version number with the reviewed draft? Save the form separately when ready." ConflictRebase)] [text "Accept comparison and return to form"]
        , button [class "btn btn-outline",onClick ConflictDismiss] [text "Keep reviewing later"]
        ])

fieldLabel : String -> String
fieldLabel key =
    case key of
        "ncFullName" -> "Client name"
        "ncEmail" -> "Email"
        "ncPhone" -> "Phone"
        "ncCaseOfficer" -> "Case officer"
        "ciServiceCategory" -> "Service"
        "ciDestination" -> "Destination"
        "ciStage" -> "Case stage"
        "ciNextDeadline" -> "Deadline"
        "ulFullName" -> "Lead name"
        "ulConsultantId" -> "Consultant"
        "uuName" -> "Staff name"
        "uuRole" -> "Role"
        "ageDays" -> "Age (days)"
        "overdueDays" -> "Overdue (days)"
        "averageAgeDays" -> "Average days in stage"
        "oldestDays" -> "Longest time in stage (days)"
        "openTasks" -> "Open tasks"
        "overdueTasks" -> "Overdue tasks"
        "openCases" -> "Open cases"
        "scanStatus" -> "Malware scan"
        "expiryWarning" -> "Expiry warning"
        "expiresOn" -> "Expires"
        "lastError" -> "Last error"
        "nextAttempt" -> "Next attempt"
        "sentAt" -> "Accepted at"
        _ -> key |> String.toList |> List.concatMap (\c -> if Char.isUpper c then [' ',Char.toLower c] else [c]) |> String.fromList |> String.trim
