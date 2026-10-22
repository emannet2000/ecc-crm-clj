module Views exposing
    ( filteredLeads
    , loginView
    , dashboardView
    , leadsView
    , leadDetailView
    , clientsView
    , clientDetailView
    , tasksView
    , usersView
    , auditView
    , userFormModal
    , passwordModal
    , notificationsDropdown
    , toastStack
    )

{-| All page views.  They are pure functions of the central Model.
-}

import Date
import Char
import Dict
import File exposing (File)
import Features
import Html exposing (Html, a, button, div, h2, h3, h4, input, label, li,
                      option, select, span, strong, table, tbody, td, text,
                      th, thead, tr, ul)
import Html.Attributes exposing (checked, class, href, placeholder, selected,
                                 type_, value)
import Html.Events exposing (on, onClick, onCheck, onInput)
import Json.Decode as D
import Set exposing (Set)

import Api
import State exposing (..)
import Types exposing (..)
import Ui exposing
    ( emptyNote
    , fmtDate
    , fmtDateTime
    , inputField
    , modal
    , priorityBadge
    , qualityTag
    , selectField
    , spinner
    , stageTag
    , statusTag
    )



-- ---------- login ----------


loginView : Model -> Html Msg
loginView model =
    let
        resetting = model.loginMode == "reset"
        recovering = model.loginMode == "recover"
        action = if resetting then ResetClicked else if recovering then RecoverClicked else LoginClicked
        heading = if resetting then "A fresh start." else if recovering then "Let’s get you back in." else "Good to see you."
        subtitle = if resetting then "Choose a new password for your account." else if recovering then "We’ll email you a secure link to reset your password." else "Sign in to your student workspace."
    in
    div [ class "login-wrap" ]
        [ div [ class "login-story" ]
            [ div [ class "login-brand" ] [ Html.img [ class "brand-emblem", Html.Attributes.src "/brand/ecc-emblem.png", Html.Attributes.alt "ECC Consulting Global", Html.Attributes.width 72, Html.Attributes.height 72 ] [], strong [] [ text "ECC" ], span [] [ text "STUDENT WORKSPACE" ] ]
            , div [ class "login-story-copy" ] [ div [ class "eyebrow" ] [ text "BUILT AROUND PEOPLE" ], Html.h1 [] [ text "Every journey.", Html.br [] [], text "A little clearer." ], Html.p [] [ text "Keep your relationships, cases and next steps together. Make every student feel remembered." ] ]
            , div [ class "login-story-footer" ] [ span [] [ text "A thoughtful way to work." ], span [] [ text "ECC / 01" ] ]
            ]
        , div [ class "login-panel" ]
            [ div [ class "login-card" ]
                [ div [ class "eyebrow" ] [ text "YOUR WORK, CONNECTED" ]
                , h2 [] [ text heading ]
                , div [ class "login-sub" ] [ text subtitle ]
                , Html.form [ Html.Events.onSubmit action ]
                    [ if resetting then span [] [] else inputField "Email address" model.loginEmail "email" LoginEmailChanged
                    , if recovering then span [] [] else inputField (if resetting then "New password · at least 12 characters" else "Password") model.loginPassword "password" LoginPasswordChanged
                    , if recovering || resetting then span [] [] else inputField "Authenticator or recovery code (if enabled)" model.loginOtp "text" LoginOtpChanged
                    , if model.loginError /= "" then div [ class "login-error", Html.Attributes.attribute "role" "alert" ] [ text model.loginError ] else span [] []
                    , if model.loginNotice /= "" then div [ class "notice-banner", Html.Attributes.attribute "role" "status" ] [ text model.loginNotice ] else span [] []
                    , button [ class "btn btn-primary login-submit", type_ "submit", Html.Attributes.disabled model.loginBusy ] [ text (if model.loginBusy then "Please wait…" else if resetting then "Set new password →" else if recovering then "Send recovery link →" else "Sign in →") ]
                    ]
                , button [ class "text-button", onClick (LoginModeChanged (if recovering || resetting then "login" else "recover")) ] [ text (if recovering || resetting then "← Back to sign in" else "Forgot your password?") ]
                , div [ class "login-hint" ]
                    [ text "Need access? Ask your workspace administrator for an invitation. "
                    , text (if recovering then "Check your spam folder. Links expire after one hour and can be used once; request a new link if necessary." else "Lost your authenticator? Use an unused recovery code in the code field. If you lost both, contact another administrator to verify your identity and reset MFA.")
                    ]
                ]
            ]
        ]


-- ---------- dashboard ----------


statCard : String -> String -> String -> String -> String -> Html Msg
statCard symbol label sub value path =
    a [ class ("stat stat-" ++ symbol), href path ]
        [ div [ class "stat-top" ] [ span [ class "stat-label" ] [ text label ], span [ class "stat-icon" ] [ Ui.icon symbol ] ]
        , div [ class "stat-value" ] [ text value ]
        , div [ class "stat-sub" ] [ span [] [ text sub ], Ui.icon "arrow" ]
        ]


dashboardView : Model -> Html Msg
dashboardView model =
    case model.stats of
        Nothing -> Ui.spinner
        Just stats ->
            let
                maxStage = List.map .count stats.stageCounts |> List.maximum |> Maybe.withDefault 1
                totalSources = List.map .count stats.sourceCounts |> List.sum |> max 1
                panelTitle title subtitle path =
                    div [ class "panel-heading" ] [ div [] [ h3 [] [ text title ], Html.p [] [ text subtitle ] ], a [ class "panel-link", href path ] [ text "View all", Ui.icon "arrow" ] ]
                stageRow sc =
                    div [ class "pipeline-row" ]
                        [ div [ class "pipeline-label" ] [ span [] [ text sc.stage ], strong [] [ text (String.fromInt sc.count) ] ]
                        , div [ class "stage-bar", Html.Attributes.attribute "role" "meter", Html.Attributes.attribute "aria-label" sc.stage, Html.Attributes.attribute "aria-valuenow" (String.fromInt sc.count), Html.Attributes.attribute "aria-valuemin" "0", Html.Attributes.attribute "aria-valuemax" (String.fromInt (max 1 maxStage)) ]
                            [ div [ class "stage-fill", Html.Attributes.style "width" (String.fromInt (round (100 * toFloat sc.count / toFloat (max 1 maxStage))) ++ "%") ] [] ]
                        ]
                sourceRow sc =
                    div [ class "source-row" ]
                        [ div [ class "source-symbol" ] [ text (String.left 1 sc.source) ]
                        , div [ class "source-info" ] [ strong [] [ text sc.source ], div [ class "source-track" ] [ div [ Html.Attributes.style "width" (String.fromInt (round (100 * toFloat sc.count / toFloat totalSources)) ++ "%") ] [] ] ]
                        , span [ class "source-count" ] [ text (String.fromInt sc.count) ]
                        ]
                taskRow task =
                    a [ class "priority-task", href (Maybe.map (\id -> "/clients/" ++ String.fromInt id) task.clientId |> Maybe.withDefault ("/leads/" ++ String.fromInt task.leadId)) ]
                        [ span [ class "task-checkbox", Html.Attributes.attribute "aria-hidden" "true" ] []
                        , div [ class "priority-task-copy" ] [ strong [] [ text task.title ], span [] [ text (Maybe.withDefault "Unlinked task" task.leadName) ] ]
                        , Ui.priorityBadge task.priority
                        , span [ class (if Maybe.withDefault "9999" task.dueDate < model.today then "due-label overdue" else "due-label") ] [ text (Ui.fmtDate task.dueDate) ]
                        , Ui.icon "arrow"
                        ]
                activityRow activity =
                    div [ class "feed-item" ]
                        [ span [ class "feed-dot", Html.Attributes.attribute "aria-hidden" "true" ] []
                        , div [ class "feed-copy" ] [ div [ class "feed-meta" ] [ span [] [ text (String.replace "_" " " activity.kind) ], span [] [ text (Ui.fmtDate (Just activity.date)) ] ], Html.p [] [ text (Maybe.withDefault "Activity recorded" activity.description) ], span [ class "text-muted" ] [ text (Maybe.withDefault "" activity.leadName) ] ]
                        ]
                orderedStages = List.concatMap (\stageName -> List.filter (\item -> item.stage == stageName) stats.stageCounts) Types.leadStages
            in
            div [ class "dashboard" ]
                [ todayView stats.today
                , div [ class "stats dashboard-stats" ]
                    [ statCard "leads" "Active leads" (String.fromInt stats.hotLeads ++ " high-priority relationships") (String.fromInt stats.totalLeads) "/leads"
                    , statCard "clients" "Students" "People you’re helping move forward" (String.fromInt stats.totalClients) "/clients"
                    , statCard "tasks" "Open tasks" "Your next steps, in one place" (String.fromInt stats.openTasks) "/tasks"
                    , statCard "clock" "Overdue tasks" (if stats.overdueTasks == 0 then "No overdue tasks" else "A little attention goes a long way") (String.fromInt stats.overdueTasks) "/tasks"
                    ]
                , div [ class (if stats.overdueTasks > 0 then "attention-strip" else "attention-strip on-track") ]
                    [ span [ class "attention-icon" ] [ Ui.icon (if stats.overdueTasks > 0 then "clock" else "check") ]
                    , div [] [ strong [] [ text (if stats.overdueTasks > 0 then String.fromInt stats.overdueTasks ++ " tasks need your attention" else "You’re on top of your tasks") ], Html.p [] [ text (if stats.overdueTasks > 0 then "Start with overdue work, then make space for what’s next." else "Keep the momentum going. Review upcoming work and follow-ups.") ] ]
                    , a [ class "attention-link", href "/tasks" ] [ text "Review tasks", Ui.icon "arrow" ]
                    ]
                , div [ class "dashboard-grid" ]
                    [ div [ class "card pipeline-panel" ]
                        [ panelTitle "Your pipeline" "Where every relationship stands" "/leads"
                        , if List.isEmpty orderedStages then Ui.emptyState "leads" "Your pipeline starts here" "Add your first lead to see your relationships take shape." else div [ class "pipeline-list" ] (List.map stageRow orderedStages)
                        ]
                    , div [ class "card sources-panel" ]
                        [ panelTitle "Where leads find you" "Your sources at a glance" "/leads"
                        , if List.isEmpty stats.sourceCounts then Ui.emptyState "clients" "No sources yet" "Sources appear when you start adding leads." else div [] (List.map sourceRow stats.sourceCounts)
                        ]
                    , div [ class "card priorities-panel" ]
                        [ panelTitle "Next on your list" "The next steps on your schedule" "/tasks"
                        , if List.isEmpty stats.upcomingTasks then Ui.emptyState "check" "A little breathing room" "No upcoming tasks. Add a next step when you’re ready." else div [ class "priority-list" ] (List.map taskRow stats.upcomingTasks)
                        ]
                    , div [ class "card activity-panel" ]
                        [ panelTitle "Latest activity" "The small steps that move things forward" "/leads"
                        , if List.isEmpty stats.recentActivity then Ui.emptyState "clock" "Your story starts here" "Notes, conversations and updates will appear as you work." else div [ class "activity-feed" ] (List.map activityRow stats.recentActivity)
                        ]
                    ]
                ]


todayView : D.Value -> Html Msg
todayView summary =
    let
        rows key = D.decodeValue (D.field key (D.list D.value)) summary |> Result.withDefault []
        count key = D.decodeValue (D.field key D.int) summary |> Result.withDefault 0
        panel title key total path empty =
            div [ class "today-panel" ]
                [ div [ class "section-head" ] [ h3 [] [ text title ], strong [ class "today-count" ] [ text (String.fromInt (count total)) ] ]
                , if List.isEmpty (rows key) then Html.p [] [ text empty ] else
                    div [ class "today-list" ] (List.map (\item -> a [ href (Features.str "path" item), class "today-item" ]
                        [ strong [] [ text (Features.str "title" item) ], span [] [ text (Features.str "detail" item) ] ]) (rows key))
                , a [ class "panel-link", href path ] [ text "View all →" ]
                ]
    in
    if D.decodeValue (D.null ()) summary == Ok () then text "" else
    div [ class "card today-overview", Html.Attributes.attribute "aria-label" "Today's priorities" ]
        [ div [ class "section-head" ] [ div [] [ h2 [] [ text "Today" ], Html.p [ class "status-help" ] [ text (Features.str "date" summary ++ " · Start with overdue work, then review deadlines and documents.") ] ] ]
        , div [ class "today-grid" ]
            [ panel "Overdue tasks" "overdueTasks" "overdueCount" "/tasks" "No overdue tasks."
            , panel "Application deadlines" "deadlines" "deadlineCount" "/applications" "No overdue applications or deadlines in the next seven days."
            , panel "Milestones due" "milestones" "milestoneCount" "/work/milestones" "No overdue milestones or planned milestones in the next seven days."
            , panel "Documents to review" "reviewDocuments" "reviewCount" "/work/documents" "No received documents awaiting review."
            ]
        , Html.p [ class "status-help" ] [ text "Shows up to five items per group, limited to records you can access. Application deadlines include overdue work and the next seven days." ]
        ]


-- ---------- leads list ----------


filteredLeads : Model -> List Lead
filteredLeads model =
    let
        qLower =
            String.toLower (String.trim model.q)

        matchesQ l =
            qLower == ""
                || String.contains qLower (String.toLower l.fullName)
                || (Maybe.map (\e -> String.contains qLower (String.toLower e)) l.email
                        |> Maybe.withDefault False
                   )
                || (Maybe.map (\p -> String.contains qLower (String.toLower p)) l.phone
                        |> Maybe.withDefault False
                   )
                || String.contains qLower (String.toLower l.number)

        matches f val =
            f == "All" || Just val == Just f

        base =
            List.filter
                (\l ->
                    matchesQ l
                        && matches model.fStage l.stage
                        && matches model.fQuality (Maybe.withDefault "" l.quality)
                        && matches model.fSource (Maybe.withDefault "" l.source)
                )
                model.leads

        keyOf l =
            case model.sortBy of
                "stage" ->
                    String.toLower l.stage

                "quality" ->
                    case l.quality of
                        Just "Hot" -> "0"

                        Just "Warm" -> "1"

                        Just "Cold" -> "2"

                        _ -> "3"

                "followup" ->
                    Maybe.withDefault "9999" l.nextFollowup

                _ ->
                    String.toLower l.fullName
    in
    List.sortWith
        (\a b ->
            if model.sortAsc then
                compare (keyOf a) (keyOf b)

            else
                compare (keyOf b) (keyOf a)
        )
        base



-- keep `dir` usable inside sortWith above


leadsToolbar : Model -> Html Msg
leadsToolbar model =
    let
        ctx =
            { base = model.apiBase, token = model.token }
    in
    div [ class "search-container" ]
        [ div [ class "search-row" ]
            [ div [ class "search-input-wrapper" ]
                [ input
                    [ class "search-input"
                    , Html.Attributes.attribute "aria-label" "Search leads"
                    , placeholder "Search name, email, phone, lead number…"
                    , value model.q
                    , onInput SearchChanged
                    ]
                    []
                ]
            , a
                [ class "btn btn-outline"
                , href (Api.exportCsvUrl ctx "leads")
                , Html.Attributes.download ""
                ]
                [ text "Export CSV" ]
            , div [ class "import-group" ]
                [ input
                    [ Html.Attributes.disabled (isReadOnly model),  type_ "file"
                    , Html.Attributes.attribute "accept" ".csv,text/csv"
                    , Html.Attributes.title "Pick a CSV of leads to import"
                    , on
                        "change"
                        (D.map ImportFilePicked
                            (D.at [ "target", "files" ] (D.index 0 File.decoder))
                        )
                    ]
                    []
                , button
                    [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-outline"
                    , Html.Attributes.title
                        (case model.pendingImport of
                            Just f ->
                                "Import " ++ File.name f

                            Nothing ->
                                "Import leads from the selected CSV file"
                        )
                    , onClick LeadImportClicked
                    ]
                    [ text
                        (case model.pendingImport of
                            Just f ->
                                "Import (" ++ File.name f ++ ")"

                            Nothing ->
                                "Import"
                        )
                    ]
                ]
            , button [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-primary", onClick OpenAddLead ] [ text "+ Add Lead" ]
            ]
        , div [ class "filter-row" ]
            [ selectFieldMsg "Stage" (plainOptions ("All" :: Types.leadStages)) model.fStage StageFilterChanged
            , selectFieldMsg "Quality" (plainOptions ("All" :: Types.qualities)) model.fQuality QualityFilterChanged
            , selectFieldMsg "Source" (plainOptions ("All" :: Types.sources)) model.fSource SourceFilterChanged
            , selectFieldMsg "Sort By"
                [ ( "name", "Name" ), ( "stage", "Stage" ), ( "quality", "Quality" ), ( "followup", "Follow-up" ) ]
                model.sortBy
                SortByChanged
            , div [ class "filter-group" ]
                [ label [] [ text "Direction" ]
                , button
                    [ class "btn btn-outline"
                    , Html.Attributes.style "width" "100%"
                    , onClick SortDirToggled
                    ]
                    [ text
                        (if model.sortAsc then
                            "↑ Ascending"

                         else
                            "↓ Descending"
                        )
                    ]
                ]
            ]
        ]


selectFieldMsg :
    String
    -> List ( String, String )
    -> String
    -> (String -> Msg)
    -> Html Msg
selectFieldMsg lbl opts current onChange =
    div [ class "filter-group" ]
        [ if lbl == "" then
            span [] []

          else
            Html.label [] [ text lbl ]
        , select [ onInput onChange ]
            (List.map
                (\( v, optLbl ) ->
                    option [ value v, selected (v == current) ] [ text optLbl ]
                )
                opts
            )
        ]


plainOptions : List String -> List ( String, String )
plainOptions =
    List.map (\s -> ( s, s ))


bulkBar : Model -> Html Msg
bulkBar model =
    if Set.isEmpty model.selected then
        div [] []

    else
        div [ class "bulk-actions" ]
        [ strong [] [ text (String.fromInt (Set.size model.selected) ++ " selected") ]
        , button [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-sm btn-success", onClick BulkAdvanceClicked ] [ text "Advance" ]
        , select [ Html.Attributes.disabled (isReadOnly model),  onInput BulkAssignPicked ]
            (option [ value "" ] [ text "Assign consultant…" ]
                :: List.map
                    (\u -> option [ value (String.fromInt u.id) ] [ text u.name ])
                    model.users
            )
        , button [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-sm btn-danger", onClick (ConfirmRequested "Archive the selected leads and preserve their history?" BulkDeleteClicked) ] [ text "Delete" ]
        ]


leadsTable : Model -> Html Msg
leadsTable model =
    let
        leads =
            filteredLeads model

        allChecked =
            not (List.isEmpty leads)
                && List.all (\l -> Set.member l.id model.selected) leads

        row l =
            tr []
                [ td []
                    [ input
                        [ type_ "checkbox"
                        , class "row-check"
                        , Html.Attributes.attribute "aria-label" ("Select " ++ l.fullName)
                        , checked (Set.member l.id model.selected)
                        , Html.Events.stopPropagationOn "click"
                            (D.succeed
                                ( RowChecked l.id (not (Set.member l.id model.selected))
                                , True
                                )
                            )
                        ]
                        []
                    ]
                , td []
                    [ a [ class "contact-identity", href ("/leads/" ++ String.fromInt l.id) ] [ Ui.avatar l.fullName, div [] [ div [ class "lead-name" ] [ text l.fullName ], div [ class "lead-source" ] [ text (Maybe.withDefault "No email added" l.email) ] ] ] ]
                , td [] [ text l.number ]
                , td [] [ Ui.stageTag l.stage ]
                , td [] [ Ui.qualityTag l.quality ]
                , td [ class "lead-source" ] [ text (Maybe.withDefault "—" l.source) ]
                , td [] [ text (Maybe.withDefault "—" l.consultantName) ]
                , td [] [ text (Ui.fmtDate l.nextFollowup) ]
                ]
    in
    if List.isEmpty leads then
        Ui.emptyState "search" "No leads to show" "Try a different search or adjust your filters. Add a lead to start a new relationship."

    else
        table [ class "data-table leads-table" ]
            [ thead []
                [ tr []
                    [ th [] [ input [ type_ "checkbox", class "row-check", Html.Attributes.attribute "aria-label" "Select all leads on this page", checked allChecked, onCheck SelectAllChecked ] [] ]
                    , th [] [ text "Lead" ]
                    , th [] [ text "Number" ]
                    , th [] [ text "Stage" ]
                    , th [] [ text "Quality" ]
                    , th [] [ text "Source" ]
                    , th [] [ text "Consultant" ]
                    , th [] [ text "Follow-up" ]
                    ]
                ]
            , tbody [] (List.map row leads)
            ]


addLeadModal : Model -> Html Msg
addLeadModal model =
    let
        f =
            model.addLead
    in
    Ui.modal "Add Lead"
        (div []
            [ checkedInputField model "fullName" "Full Name *" f.fullName "text" (\v -> UpdateAddLead (\g -> { g | fullName = v }))
            , checkedInputField model "email" "Email" f.email "email" (\v -> UpdateAddLead (\g -> { g | email = v }))
            , checkedInputField model "phone" "Phone" f.phone "tel" (\v -> UpdateAddLead (\g -> { g | phone = v }))
            , selectField "Source" Types.sources f.source (\v -> UpdateAddLead (\g -> { g | source = v }))
            , selectField "Quality" Types.qualities f.quality (\v -> UpdateAddLead (\g -> { g | quality = v }))
            , selectField "Stage" Types.leadStages f.stage (\v -> UpdateAddLead (\g -> { g | stage = v }))
            , selectField "Destination" Types.destinations f.destination (\v -> UpdateAddLead (\g -> { g | destination = v }))
            , selectField "Service" Types.services f.service (\v -> UpdateAddLead (\g -> { g | service = v }))
            , checkedInputField model "nextFollowup" "Next Follow-up" f.nextFollowup "date" (\v -> UpdateAddLead (\g -> { g | nextFollowup = v }))
            , inputField "Notes" f.notes "text" (\v -> UpdateAddLead (\g -> { g | notes = v }))
            , div [ class "flex", Html.Attributes.style "margin-top" "14px" ]
                [ button [ Html.Attributes.disabled (isReadOnly model || model.featureBusy),  class "btn btn-primary", onClick SubmitAddLead ] [ text "Save Lead" ]
                , button [ class "btn btn-outline", onClick CloseAddLead ] [ text "Cancel" ]
                ]
            ]
        )


leadsView : Model -> Html Msg
leadsView model =
    div []
        [ div [ class "page-head" ]
            [ h2 [] [ text "Leads" ]
            , div [ class "results-summary" ]
                [ text (String.fromInt (List.length (filteredLeads model)) ++ " shown")
                ]
            ]
        , leadsToolbar model
        , bulkBar model
        , div [ class "card table-card", Html.Attributes.style "margin-top" "12px" ]
            [ leadsTable model ]
        , if model.showAddLead then
            addLeadModal model

          else
            div [] []
        ]



-- ---------- lead detail ----------


leadDetailView : Model -> Int -> Html Msg
leadDetailView model id =
    case model.detail of
        Nothing ->
            Ui.spinner

        Just detail ->
            let
                l =
                    detail.lead
            in
            div []
                [ a [ class "back-link", href "#", onClick (NavigateTo "/leads") ] [ text "← Back to Leads" ]
                , div [ class "page-head" ]
                    [ div []
                        [ h2 [] [ text l.fullName ]
                        , div [ class "lead-detail-badges" ]
                            [ span [ class "tag tag-id" ] [ text l.number ]
                            , Ui.stageTag l.stage
                            , Ui.qualityTag l.quality
                            ]
                        ]
                    , div [ class "flex" ]
                        [ button [ Html.Attributes.disabled (isReadOnly model),  class "btn", onClick EditLeadToggled ]
                            [ text
                                (if model.editLeadOpen then
                                    "Close Editor"

                                 else
                                    "Edit"
                                )
                            ]
                        , button [ Html.Attributes.disabled (isReadOnly model),  class "btn", onClick (AdvanceClicked l.id) ] [ text "Advance ▸" ]
                        , button [ Html.Attributes.disabled (isReadOnly model || model.featureBusy), class "btn btn-primary", onClick (ConfirmRequested "Convert this lead to a student? Documents, tasks and history will be preserved." (ConvertClicked l.id)) ] [ text (if model.featureBusy then "Converting…" else "Convert to student") ]
                        , button [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-danger", onClick (ConfirmRequested "Move this lead to the archive? Its history will be preserved." (DeleteLeadConfirmed l.id)) ] [ text "Delete" ]
                        ]
                    ]
                , div [ class "detail-grid" ]
                    [ div [ class "card" ]
                        [ div [ class "section-head" ] [ h3 [] [ text "Contact & Pipeline" ] ]
                        , if model.editLeadOpen then
                            editLeadForm model model.editLead

                          else
                            contactGrid detail
                        ]
                    , div [ class "card" ]
                        [ div [ class "section-head" ]
                            [ h3 [] [ text "Tasks" ]
                            , button [ class "btn btn-sm btn-outline", onClick (UpdateAddTask (\f -> { f | title = f.title })) ]
                                [ text "+" ]
                            ]
                        , addTaskInline model id
                        , taskRows model detail.tasks
                        ]
                    ]
                , div [ class "detail-grid", Html.Attributes.style "margin-top" "16px" ]
                    [ documentsCard model detail.documents (UploadLeadDocClicked id)
                    ]
                , div [ class "card", Html.Attributes.style "margin-top" "16px" ]
                    [ div [ class "section-head" ] [ h3 [] [ text "Activity Timeline" ] ]
                    , noteComposer model id
                    , timeline detail.activities
                    ]
                ]


contactGrid : LeadDetail -> Html msg
contactGrid detail =
    let
        l =
            detail.lead

        kv k v =
            div [ class "kv" ]
                [ div [] [ text k ]
                , div [] [ text v ]
                ]
    in
    div [ class "kv-grid" ]
        [ kv "Email" (Maybe.withDefault "—" l.email)
        , kv "Phone" (Maybe.withDefault "—" l.phone)
        , kv "Source" (Maybe.withDefault "—" l.source)
        , kv "Destination" (Maybe.withDefault "—" l.destination)
        , kv "Service" (Maybe.withDefault "—" l.service)
        , kv "Consultant" (Maybe.withDefault "—" l.consultantName)
        , kv "Last Contact" (Ui.fmtDate l.lastContact)
        , kv "Next Follow-up" (Ui.fmtDate l.nextFollowup)
        , kv "Notes" (Maybe.withDefault "—" l.notes)
        ]


editLeadForm : Model -> EditLeadForm -> Html Msg
editLeadForm model f =
    div []
        [ checkedInputField model "fullName" "Full Name" f.fullName "text" (\v -> UpdateEditLead (\g -> { g | fullName = v }))
        , checkedInputField model "email" "Email" f.email "email" (\v -> UpdateEditLead (\g -> { g | email = v }))
        , checkedInputField model "phone" "Phone" f.phone "tel" (\v -> UpdateEditLead (\g -> { g | phone = v }))
        , selectField "Stage" Types.leadStages f.stage (\v -> UpdateEditLead (\g -> { g | stage = v }))
        , selectField "Quality" Types.qualities f.quality (\v -> UpdateEditLead (\g -> { g | quality = v }))
        , selectField "Source" Types.sources f.source (\v -> UpdateEditLead (\g -> { g | source = v }))
        , selectField "Destination" Types.destinations f.destination (\v -> UpdateEditLead (\g -> { g | destination = v }))
        , selectField "Service" Types.services f.service (\v -> UpdateEditLead (\g -> { g | service = v }))
        , checkedInputField model "lastContact" "Last Contact" f.lastContact "date" (\v -> UpdateEditLead (\g -> { g | lastContact = v }))
        , checkedInputField model "nextFollowup" "Next Follow-up" f.nextFollowup "date" (\v -> UpdateEditLead (\g -> { g | nextFollowup = v }))
        , div [ class "form-group", Html.Attributes.style "grid-column" "1 / -1" ]
            [ label [] [ text "Notes" ]
            , Html.textarea
                [ class "input"
                , Html.Attributes.rows 3
                , value f.notes
                , onInput (\v -> UpdateEditLead (\g -> { g | notes = v }))
                ]
                []
            ]
        , div [ class "flex", Html.Attributes.style "grid-column" "1 / -1", Html.Attributes.style "margin-top" "8px" ]
            [ button [ Html.Attributes.disabled (isReadOnly model || model.featureBusy),  class "btn btn-primary", onClick SubmitEditLead ] [ text "Save Changes" ]
            , button [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-outline", onClick EditLeadToggled ] [ text "Cancel" ]
            ]
        ]


addTaskInline : Model -> Int -> Html Msg
addTaskInline model leadId =
    taskComposer model (SubmitAddTaskFor leadId)


taskComposer : Model -> Msg -> Html Msg
taskComposer model submitMsg =
    div [ class "inline-form", Html.Attributes.style "margin-bottom" "10px" ]
        [ div [ class "form-group", Html.Attributes.style "flex" "2" ]
            [ input
                [ class "input"
                , placeholder "New task title…"
                , value model.addTask.title
                , onInput (\v -> UpdateAddTask (\f -> { f | title = v }))
                ]
                []
            ]
        , div [ class "form-group" ]
            [ input
                [ type_ "date"
                , class "input"
                , value model.addTask.dueDate
                , onInput (\v -> UpdateAddTask (\f -> { f | dueDate = v }))
                ]
                []
            ]
        , selectFieldMsg "" (plainOptions Types.priorities) model.addTask.priority
            (\v -> UpdateAddTask (\f -> { f | priority = v }))
        , button [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-sm btn-primary", onClick submitMsg ]
            [ text "Add Task" ]
        ]


taskRows : Model -> List Task -> Html Msg
taskRows model tasks =
    if List.isEmpty tasks then
        Ui.emptyNote "No tasks yet."

    else
        div []
            (List.map
                (\t ->
                    div [ class "task-row" ]
                        [ select
                            [ Html.Attributes.disabled (isReadOnly model),  Html.Attributes.style "padding" "4px"
                            , Html.Attributes.style "border-radius" "6px"
                            , Html.Attributes.attribute "aria-label" ("Status for " ++ t.title)
                            , onInput (TaskStatusPicked t.id)
                            ]
                            (List.map
                                (\s ->
                                    option [ value s, selected (s == t.status) ] [ text s ]
                                )
                                Types.taskStatuses
                            )
                        , span
                            [ class
                                (if t.status == "Done" then
                                    "done-title"

                                 else
                                    ""
                                )
                            ]
                            [ text t.title ]
                        , Ui.priorityBadge t.priority
                        , span [ class "activity-date" ] [ text (Ui.fmtDate t.dueDate) ]
                        , button
                            [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-sm btn-outline"
                            , onClick (ConfirmRequested "Delete this task? This action cannot be undone." (TaskDeleted t.id))
                            ]
                            [ text "✕" ]
                        ]
                )
                tasks
            )


noteComposer : Model -> Int -> Html Msg
noteComposer model leadId =
    div [ class "add-note", Html.Attributes.style "margin-bottom" "12px" ]
        [ input
            [ class "input"
            , placeholder "Log a note, call summary…"
            , value model.noteDraft
            , onInput NoteDraftChanged
            ]
            []
        , button [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-sm btn-primary", onClick (NoteSubmitted leadId) ]
            [ text "Add Note" ]
        ]


timeline : List Activity -> Html Msg
timeline activities =
    if List.isEmpty activities then
        Ui.emptyNote "No activity recorded."

    else
        div []
            (List.map
                (\act ->
                    div [ class "tl-item" ]
                        [ span [ class "tl-date" ] [ text act.date ]
                        , span [ class "tl-type" ] [ text act.kind ]
                        , span [ class "activity-desc" ] [ text (Maybe.withDefault "" act.description) ]
                        ]
                )
                activities
            )



-- ---------- documents ----------


{-| File picker + list of uploaded documents.  @uploadMsg@ decides whether
the file attaches to the lead or the client shown on the current page.
-}
documentsCard : Model -> List Document -> Msg -> Html Msg
documentsCard model docs uploadMsg =
    div [ class "card" ]
        [ div [ class "section-head" ]
            [ h3 [] [ text "Documents" ]
            , span [ class "lead-count" ] [ text (String.fromInt (List.length docs)) ]
            ]
        , div [ class "inline-form", Html.Attributes.style "margin-bottom" "10px" ]
            [ input
                [ Html.Attributes.disabled (isReadOnly model),  type_ "file"
                , on
                    "change"
                    (D.map DocPicked
                        (D.at [ "target", "files" ] (D.index 0 File.decoder))
                    )
                ]
                []
            , span [ class "empty-note" ]
                [ text
                    (case model.pendingDoc of
                        Just file ->
                            File.name file

                        Nothing ->
                            "No file chosen"
                    )
                ]
            , button [ Html.Attributes.disabled (isReadOnly model || model.documentBusy || model.pendingDoc == Nothing), class "btn btn-sm btn-primary", onClick uploadMsg ]
                [ text (if model.documentBusy then "Uploading…" else "Upload") ]
            ]
        , Html.p [class "status-help", Html.Attributes.attribute "role" "status"] [text (if model.documentBusy then "Uploading your file. Please wait before leaving this record." else "Files up to 25 MB are scanned before download. Failed scans need an administrator’s retry; infected files need a safe replacement.")]
        , documentRows model docs
        ]


documentRows : Model -> List Document -> Html Msg
documentRows model docs =
    if List.isEmpty docs then
        Ui.emptyNote "No documents yet — upload a passport, form, or scan."

    else
        div [] (List.map (documentRow model) docs)


documentRow : Model -> Document -> Html Msg
documentRow model d =
    let
        ctx =
            { base = model.apiBase, token = model.token }
    in
    div [ class "task-row" ]
        [ span [ Html.Attributes.title d.filename ]
            [ strong [] [ text d.filename ] ]
        , span [ class "activity-date" ] [ text (fmtSize d.size) ]
        , span [ class "activity-date" ] [ text (String.left 10 d.createdAt) ]
        , span [] [ text (Maybe.withDefault "" d.uploaderName) ]
        , if d.scanStatus/="Clean" then span [class "tag"] [text ("Scan: " ++ d.scanStatus ++ (if d.scanStatus == "Error" then " · Ask an administrator to retry" else if d.scanStatus == "Infected" then " · Upload a safe replacement" else " · Download unavailable until scanning passes"))] else a
            [ class "btn btn-sm btn-outline"
            , href (Api.documentDownloadUrl ctx d.id)
            , Html.Attributes.download ""
            ]
            [ text "Download" ]
        , button [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-sm btn-danger", onClick (ConfirmRequested "Delete this document? This action cannot be undone." (DocDeleted d.id)) ]
            [ text "Delete" ]
        ]



-- ---------- clients list ----------


clientsView : Model -> Html Msg
clientsView model =
    let
        q =
            String.toLower (String.trim model.clientQ)

        visible =
            List.filter
                (\c ->
                    q == ""
                        || String.contains q (String.toLower c.fullName)
                        || String.contains q (String.toLower c.number)
                )
                model.clients

        row c =
            tr []
                [ td []
                    [ a [ class "contact-identity", href ("/clients/" ++ String.fromInt c.id) ] [ Ui.avatar c.fullName, div [] [ div [ class "lead-name" ] [ text c.fullName ], div [ class "lead-source" ] [ text (Maybe.withDefault "No email added" c.email) ] ] ] ]
                , td [ Html.Attributes.attribute "data-label" "Student number" ] [ text c.number ]
                , td [ Html.Attributes.attribute "data-label" "Phone" ] [ text (Maybe.withDefault "—" c.phone) ]
                , td [ Html.Attributes.attribute "data-label" "Case officer" ] [ text (Maybe.withDefault "—" c.caseOfficerName) ]
                , td [ class "lead-source", Html.Attributes.attribute "data-label" "Student since" ] [ text (Ui.fmtDateTime c.createdAt) ]
                ]
    in
    div []
        [ div [ class "page-head" ]
            [ h2 [] [ text "Students" ]
            , div [ class "flex" ]
                [ a
                    [ class "btn btn-outline"
                    , href (Api.exportCsvUrl
                                { base = model.apiBase, token = model.token }
                                "clients")
                    , Html.Attributes.download ""
                    ]
                    [ text "Export CSV" ]
                , button [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-primary", onClick OpenAddClient ] [ text "+ Add Student" ]
                ]
            ]
        , div [ class "search-container" ]
            [ div [ class "search-row" ]
                [ div [ class "search-input-wrapper" ]
                    [ input
                        [ class "search-input"
                        , Html.Attributes.attribute "aria-label" "Search students"
                        , placeholder "Search students…"
                        , value model.clientQ
                        , onInput ClientSearchChanged
                        ]
                        []
                    ]
                ]
            ]
        , div [ class "card table-card", Html.Attributes.style "margin-top" "12px" ]
            [ if List.isEmpty visible then
                Ui.emptyState "clients" "No students to show" "Try another search, add a student, or convert a qualified lead."

              else
                table [ class "data-table students-table clients-table" ]
                    [ thead []
                        [ tr []
                            [ th [ Html.Attributes.scope "col" ] [ text "Record" ]
                            , th [ Html.Attributes.scope "col" ] [ text "Number" ]
                            , th [ Html.Attributes.scope "col" ] [ text "Phone" ]
                            , th [ Html.Attributes.scope "col" ] [ text "Case Officer" ]
                            , th [ Html.Attributes.scope "col" ] [ text "Since" ]
                            ]
                        ]
                    , tbody [] (List.map row visible)
                    ]
            ]
        , if model.showClientForm then
            clientFormModal model

          else
            div [] []
        ]


clientFormModal : Model -> Html Msg
clientFormModal model =
    let
        f =
            model.clientForm

        title =
            case model.clientEditingId of
                Just _ ->
                    "Edit Student"

                Nothing ->
                    "Add Student"
    in
    Ui.modal title
        (div []
            [ checkedInputField model "fullName" "Full Name *" f.fullName "text" (\v -> UpdateClientForm (\g -> { g | fullName = v }))
            , checkedInputField model "email" "Email" f.email "email" (\v -> UpdateClientForm (\g -> { g | email = v }))
            , checkedInputField model "phone" "Phone" f.phone "tel" (\v -> UpdateClientForm (\g -> { g | phone = v }))
            , div [ class "form-group" ]
                [ label [] [ text "Case Officer" ]
                , select
                    [ onInput (\v -> UpdateClientForm (\g -> { g | officerId = v })) ]
                    (option [ value "" ] [ text "Assign to me by default" ]
                        :: List.map
                            (\u -> option
                                [ value (String.fromInt u.id)
                                , selected (Maybe.withDefault "" (Maybe.map String.fromInt (Just u.id)) == f.officerId)
                                ]
                                [ text u.name ]
                            )
                            model.users
                    )
                ]
            , div [ class "flex", Html.Attributes.style "margin-top" "14px" ]
                [ button [ Html.Attributes.disabled (isReadOnly model || model.featureBusy),  class "btn btn-primary", onClick SubmitClientForm ] [ text "Save" ]
                , button [ class "btn btn-outline", onClick CloseClientForm ] [ text "Cancel" ]
                ]
            ]
        )



-- ---------- client detail ----------


clientDetailView : Model -> Int -> Html Msg
clientDetailView model cid =
    case model.clientDetail of
        Nothing ->
            Ui.spinner

        Just cd ->
            let
                c =
                    cd.client

                caseRow cr =
                    tr []
                        [ td [ Html.Attributes.attribute "data-label" "Service" ] [ text (Maybe.withDefault "—" cr.category) ]
                        , td [ Html.Attributes.attribute "data-label" "Destination" ] [ text (Maybe.withDefault "—" cr.destination) ]
                        , td [ Html.Attributes.attribute "data-label" "Stage" ] [ span [ class "tag tag-stage-blue" ] [ text cr.stage ] ]
                        , td [ Html.Attributes.attribute "data-label" "Deadline" ] [ text (Ui.fmtDate cr.deadline) ]
                        , td []
                            [ button
                                [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-sm btn-outline"
                                , onClick (OpenCaseForm (Just cr))
                                ]
                                [ text "Edit" ]
                            ]
                        , td []
                            [ button
                                [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-sm btn-danger"
                                , onClick (ConfirmRequested "Delete this case? This action cannot be undone." (DeleteCaseClicked cr.id))
                                ]
                                [ text "Delete" ]
                            ]
                        ]
            in
            div [ class "client-detail-page" ]
                [ a [ class "back-link", href "/clients" ] [ text "← Back to Students" ]
                , div [ class "page-head" ]
                    [ div []
                        [ h2 [] [ text c.fullName ]
                        , div [ class "lead-detail-badges" ]
                            [ span [ class "tag tag-id" ] [ text c.number ]
                            ]
                        ]
                    , div [ class "flex" ]
                        [ button [ Html.Attributes.disabled (isReadOnly model),  class "btn", onClick (OpenCaseForm Nothing) ] [ text "+ Add Application" ]
                        , button
                            [ Html.Attributes.disabled (isReadOnly model),  class "btn"
                            , onClick (OpenClientEditor c.id)
                            ]
                            [ text "Edit" ]
                        , button [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-danger", onClick (ConfirmRequested "Move this student to the archive? Its applications, documents and history will be preserved." (DeleteClientConfirmed c.id)) ] [ text "Delete" ]
                        ]
                    ]
                , Features.clientNextSteps model c.id
                , div [ class "detail-grid" ]
                    [ div [ class "card" ]
                        [ div [ class "section-head" ] [ h3 [] [ text "Details" ] ]
                        , div [ class "kv-grid" ]
                            [ div [ class "kv" ] [ div [] [ text "Email" ], div [] [ Maybe.map (\email -> a [ href ("mailto:" ++ email) ] [ text email ]) c.email |> Maybe.withDefault (text "—") ] ]
                            , div [ class "kv" ] [ div [] [ text "Phone" ], div [] [ Maybe.map (\phone -> a [ href ("tel:" ++ phone) ] [ text phone ]) c.phone |> Maybe.withDefault (text "—") ] ]
                            , div [class "kv student-contact-actions"] [div [] [text "Contact"],div [] [studentContactLinks c.phone]]
                            , div [ class "kv" ] [ div [] [ text "Case Officer" ], div [] [ text (Maybe.withDefault "—" c.caseOfficerName) ] ]
                            , div [ class "kv" ] [ div [] [ text "Since" ], div [] [ text (Ui.fmtDateTime c.createdAt) ] ]
                            ]
                        ]
                    , div [ class "card table-card" ]
                        [ div [ class "section-head" ] [ h3 [] [ text "Applications" ] ]
                        , if List.isEmpty cd.cases then
                            Ui.emptyNote "No applications yet — add one."

                          else
                            table [ class "data-table client-applications-table" ]
                                [ thead []
                                    [ tr []
                                        [ th [ Html.Attributes.scope "col" ] [ text "Service" ]
                                        , th [ Html.Attributes.scope "col" ] [ text "Destination" ]
                                        , th [ Html.Attributes.scope "col" ] [ text "Stage" ]
                                        , th [ Html.Attributes.scope "col" ] [ text "Deadline" ]
                                        , th [] []
                                        , th [] []
                                        ]
                                    ]
                                , tbody [] (List.map caseRow cd.cases)
                                ]
                        ]
                    ]
                , Features.clientPhotoCard model c.id
                , div [ class "detail-grid", Html.Attributes.style "margin-top" "16px" ]
                    [ documentsCard model cd.documents (UploadClientDocClicked cd.client.id)
                    , div [ class "card", Html.Attributes.id "client-tasks" ] [ div [ class "section-head" ] [ h3 [] [ text "Tasks & follow-ups" ], button [ class "btn btn-sm btn-outline", onClick (NavigateTo "/tasks") ] [ text "Manage tasks ↗" ] ], taskComposer model (SubmitClientTask cd.client.id), taskRows model cd.tasks ]
                    , div [ class "card" ] [ h3 [] [ text "Journey history" ], if List.isEmpty cd.activities then Ui.emptyNote "Activity will appear here as the relationship grows." else div [] (List.map (\activity -> div [ class "activity-item" ] [ span [ class "activity-date" ] [ text activity.date ], text (Maybe.withDefault "" activity.description) ]) cd.activities) ]
                    ]
                , Features.embedded model cid
                , if model.showClientForm then clientFormModal model else text ""
                , case model.caseForm of
                    Just cf ->
                        caseModal model cf cd

                    Nothing ->
                        div [] []
                ]


{-| Human-readable file size, rounded down to the nearest unit.
-}
fmtSize : Int -> String
fmtSize bytes =
    if bytes >= 1048576 then
        String.fromInt (bytes // 1048576) ++ " MB"

    else if bytes >= 1024 then
        String.fromInt (bytes // 1024) ++ " KB"

    else
        String.fromInt bytes ++ " B"


caseModal : Model -> CaseForm -> ClientDetail -> Html Msg
caseModal model cf cd =
    Ui.modal
        (if cf.caseId == Nothing then
            "Add Application"

         else
            "Edit Application"
        )
        (div []
            [ selectField "Service Category" Types.services cf.category
                (\v -> UpdateCaseForm (\f -> { f | category = v }))
            , selectField "Destination" Types.destinations cf.destination
                (\v -> UpdateCaseForm (\f -> { f | destination = v }))
            , selectField "Stage" Types.caseStages cf.stage
                (\v -> UpdateCaseForm (\f -> { f | stage = v }))
            , checkedInputField model "deadline" "Next Deadline" cf.deadline "date"
                (\v -> UpdateCaseForm (\f -> { f | deadline = v }))
            , div [ class "flex", Html.Attributes.style "margin-top" "14px" ]
                [ button [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-primary", onClick (SubmitCaseForm cd.client.id) ] [ text "Save Application" ]
                , button [ class "btn btn-outline", onClick CloseCaseForm ] [ text "Cancel" ]
                ]
            ]
        )



-- ---------- tasks page ----------


tasksView : Model -> Html Msg
tasksView model =
    let
        section status =
            let
                items =
                    List.filter (\t -> t.status == status) model.tasks
            in
            div [ class ("card task-column task-column-" ++ String.toLower (String.replace " " "-" status)) ]
                [ div [ class "section-head" ]
                    [ h3 [] [ span [ class "status-dot", Html.Attributes.attribute "aria-hidden" "true" ] [], text status ]
                    , span [ class "lead-count" ] [ text (String.fromInt (List.length items)) ]
                    ]
                , if List.isEmpty items then
                    Ui.emptyState "check" "Nothing here yet" "Tasks appear here as work moves forward."

                  else
                    div []
                        (List.map
                            (\t ->
                                div [ class "task-row" ]
                                    [ select
                                        [ Html.Attributes.disabled (isReadOnly model),  Html.Attributes.style "padding" "4px"
                                        , Html.Attributes.attribute "aria-label" ("Status for " ++ t.title)
                            , onInput (TaskStatusPicked t.id)
                                        ]
                                        (List.map
                                            (\s ->
                                                option [ value s, selected (s == t.status) ]
                                                    [ text s ]
                                            )
                                            Types.taskStatuses
                                        )
                                    , span
                                        [ class
                                            (if t.status == "Done" then
                                                "done-title"

                                             else
                                                ""
                                            )
                                        ]
                                        [ strong [] [ text t.title ] ]
                                    , a
                                        [ class "task-lead"
                                        , href (Maybe.map (\id -> "/clients/" ++ String.fromInt id) t.clientId |> Maybe.withDefault ("/leads/" ++ String.fromInt t.leadId))
                                        ]
                                        [ text (Maybe.withDefault "" t.leadName) ]
                                    , span [class "task-assignee"] [text (Maybe.withDefault "Unassigned" t.assigneeName)]
                                    , if isReadOnly model then text "" else button [class "btn btn-sm btn-outline", onClick (EditTask t)] [text "Edit / assign"]
                                    , Ui.priorityBadge t.priority
                                    , span [ class "activity-date" ] [ text (Ui.fmtDate t.dueDate) ]
                                    , button [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-sm btn-outline", onClick (ConfirmRequested "Delete this task? This action cannot be undone." (TaskDeleted t.id)) ]
                                        [ text "✕" ]
                                    ]
                            )
                            items
                        )
                ]
    in
    div []
        [ div [ class "page-head" ]
            [ h2 [] [ text "Tasks" ]
            , button [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-primary", onClick ToggleGlobalAddTask ]
                [ text
                    (if model.showGlobalAddTask then
                        "Close"

                     else
                        "+ New Task"
                    )
                ]
            ]
        , if model.showGlobalAddTask then
            globalAddTaskForm model

          else
            div [] []
        , if model.editingTask then taskEditor model else text ""
        , if isReadOnly model then div [class "notice-banner"] [text "You can view tasks. Ask a consultant or administrator to create, assign or complete work."] else text ""
        , div [ class "task-board" ]
            [ section "Pending"
            , section "In Progress"
            , section "Done"
            ]
        ]


globalAddTaskForm : Model -> Html Msg
globalAddTaskForm model =
    div [ class "card", Html.Attributes.style "margin-bottom" "16px" ]
        [ h3 [] [text "Create and assign a task"]
        , taskFieldError model "owner"
        , div [ class "inline-form" ]
            [ div [ class "form-group", Html.Attributes.style "flex" "1.5" ]
                [ label [] [ text "Lead or student" ]
                , select
                    [ onInput (\v -> UpdateAddTask (\f -> { f | leadId = v })) ]
                    (option [ value "" ] [ text "Choose a lead or student…" ]
                        :: List.map
                            (\l ->
                                option
                                    [ value (String.fromInt l.id)
                                    , selected (model.addTask.leadId == String.fromInt l.id)
                                    ]
                                    [ text (l.number ++ " — " ++ l.fullName) ]
                            )
                            model.leads
                        ++ List.map (\client -> option [ value ("client:" ++ String.fromInt client.id), selected (model.addTask.leadId == "client:" ++ String.fromInt client.id) ] [ text ("Student · " ++ client.fullName) ]) model.clients
                    )
                ]
            , div [ class "form-group", Html.Attributes.style "flex" "2" ]
                [ input
                    [ class "input"
                    , placeholder "Task title…"
                    , value model.addTask.title
                    , onInput (\v -> UpdateAddTask (\f -> { f | title = v }))
                    ]
                    []
                ]
            , div [ class "form-group" ]
                [ input
                    [ type_ "date"
                    , class "input"
                    , value model.addTask.dueDate
                    , onInput (\v -> UpdateAddTask (\f -> { f | dueDate = v }))
                    ]
                    []
                ]
            , selectFieldMsg "" (plainOptions Types.priorities) model.addTask.priority
                (\v -> UpdateAddTask (\f -> { f | priority = v }))
            , div [class "form-group"]
                [ label [Html.Attributes.for "new-task-assignee"] [text "Assign to"]
                , select [Html.Attributes.id "new-task-assignee", value model.addTask.assignee, onInput (\v -> UpdateAddTask (\f -> { f | assignee = v }))]
                    (option [value ""] [text "Choose staff…"] :: List.map (\u -> option [value (String.fromInt u.id), selected (model.addTask.assignee == String.fromInt u.id)] [text (u.name ++ " · " ++ u.email)]) (List.filter (\u -> u.role /= "viewer") model.users))
                ]
            , inputField "Repeat every days (optional)" model.addTask.recurrenceDays "number" (\v -> UpdateAddTask (\f -> { f | recurrenceDays = v }))
            , button [ Html.Attributes.disabled (isReadOnly model || model.featureBusy), class "btn btn-primary", onClick SubmitAddTaskGlobal ] [ text (if model.featureBusy then "Creating…" else "Create task") ]
            ]
        , div [class "form-feedback"] (List.map (taskFieldError model) ["title","assignee","dueDate","recurrenceDays"])
        , if model.featureError /= "" then div [class "error-banner", Html.Attributes.attribute "role" "alert"] [text model.featureError] else text ""
        ]


taskFieldError : Model -> String -> Html Msg
taskFieldError model key =
    case Dict.get key model.featureErrors of
        Just message -> Html.p [Html.Attributes.id ("task-error-" ++ key), class "field-error", Html.Attributes.attribute "role" "alert"] [text message]
        Nothing -> text ""


taskEditor : Model -> Html Msg
taskEditor model =
    let
        get key = Dict.get key model.featureForm |> Maybe.withDefault ""
        field labelText key kind =
            div [] [inputField labelText (get key) kind (FeatureField key), taskFieldError model key]
    in
    Ui.modal "Edit and assign task"
        (Html.fieldset [Html.Attributes.disabled model.featureBusy, class "editor-fields"]
            [ field "Task title" "title" "text"
            , field "Description" "description" "text"
            , field "Due date" "dueDate" "date"
            , selectField "Priority" (Types.priorities ++ ["Urgent"]) (get "priority") (FeatureField "priority")
            , selectField "Status" Types.taskStatuses (get "status") (FeatureField "status")
            , div [class "form-group"]
                [ label [Html.Attributes.for "task-editor-assignee"] [text "Assign to"]
                , select [Html.Attributes.id "task-editor-assignee", value (get "assignee"), Html.Attributes.disabled model.featureBusy, onInput (FeatureField "assignee")]
                    (option [value ""] [text "Choose staff…"] :: List.map (\u -> option [value (String.fromInt u.id), selected (get "assignee" == String.fromInt u.id)] [text (u.name ++ " · " ++ u.email)]) (List.filter (\u -> u.role /= "viewer") model.users))
                , taskFieldError model "assignee"
                ]
            , field "Repeat every days (optional)" "recurrenceDays" "number"
            , if model.featureError /= "" then div [class "error-banner", Html.Attributes.attribute "role" "alert"] [text model.featureError] else text ""
            , div [class "form-actions"]
                [ button [class "btn btn-primary", Html.Attributes.disabled model.featureBusy, onClick (FeatureRun "save")] [text (if model.featureBusy then "Please wait…" else "Save task")]
                , button [class "btn btn-outline", Html.Attributes.disabled model.featureBusy, onClick CloseTaskEditor] [text "Cancel"]
                ]
            ]
        )


-- ---------- users & account ----------


{-| Admin-only user management page.
-}
usersView : Model -> Html Msg
usersView model =
    let
        me_ =
            Maybe.withDefault { id = 0, email = "", name = "", role = "", revision = 1, mfaRequired = False } model.user
    in
    if me_.role /= "admin" then
        div [ class "card" ]
            [ Ui.emptyNote "Admin access required." ]

    else
        let
            userRow u =
                tr []
                    [ td [] [ text u.name ]
                    , td [] [ text u.email ]
                    , td []
                        [ span
                            [ class
                                (if u.role == "admin" then
                                    "tag tag-hot"

                                 else if u.role == "viewer" then
                                    "tag tag-cold"

                                 else
                                    "tag tag-warm"
                                )
                            ]
                            [ text u.role ]
                        ]
                    , td []
                        [ button
                            [ class "btn btn-sm btn-outline"
                            , onClick (OpenUserEditor u.id)
                            ]
                            [ text "Edit" ]
                        , button [ class "btn btn-sm btn-outline", onClick (RunOperation ("users/" ++ String.fromInt u.id ++ "/invite")) ] [ text "Send invitation" ]
                        ]
                    , td []
                        [ button
                            [ class "btn btn-sm btn-danger"
                            , onClick (ConfirmRequested "Delete this account and revoke its sessions? Existing activity will remain in the audit trail." (DeleteUserConfirmed u.id))
                            , Html.Attributes.disabled (u.id == me_.id)
                            ]
                            [ text
                                (if u.id == me_.id then
                                    "You"

                                 else
                                    "Delete"
                                )
                            ]
                        ]
                    ]
        in
        div []
            [ div [ class "page-head" ]
                [ div []
                    [ h2 [] [ text "Users" ]
                    , span [ class "empty-note" ]
                        [ text "Admins manage accounts. Viewers are read-only. Set record access and privileges in Account security → Team access."
                        , a [ href "/work/security", class "btn btn-sm btn-outline" ] [ text "Manage access and privileges" ]
                        ]
                    ]
                , div [ class "flex" ]
                    [ button [ class "btn btn-primary", onClick OpenAddUser ]
                        [ text "+ Add User" ]
                    ]
                ]
            , div [ class "card table-card" ]
                [ table [ class "data-table" ]
                    [ thead []
                        [ tr []
                            [ th [] [ text "Name" ]
                            , th [] [ text "Email" ]
                            , th [] [ text "Role" ]
                            , th [] []
                            , th [] []
                            ]
                        ]
                    , tbody [] (List.map userRow model.users)
                    ]
                ]
            ]


userFormModal : Model -> Html Msg
userFormModal model =
    let
        f =
            model.userForm

        editing =
            f.userId /= Nothing

        pwField =
            if editing then
                checkedInputField model "password" "Password (leave blank to keep current)" f.password "password"
                    (\v -> UpdateUserForm (\g -> { g | password = v }))

            else
                checkedInputField model "password" "Password (12+ characters, or leave blank to email an invitation)" f.password "password"
                    (\v -> UpdateUserForm (\g -> { g | password = v }))
    in
    Ui.modal
        (if editing then
            "Edit User"

         else
            "Add User"
        )
        (div []
            [ checkedInputField model "name" "Full Name" f.name "text"
                (\v -> UpdateUserForm (\g -> { g | name = v }))
            , if editing then
                div [ class "form-group" ]
                    [ label [] [ text "Email" ]
                    , div [ class "input", Html.Attributes.style "color" "#5B6572" ]
                        [ text f.email ]
                    ]

              else
                checkedInputField model "email" "Email" f.email "email"
                    (\v -> UpdateUserForm (\g -> { g | email = v }))
            , selectField "Role" Types.roles f.role
                (\v -> UpdateUserForm (\g -> { g | role = v }))
            , pwField
            , div [ class "flex", Html.Attributes.style "margin-top" "14px" ]
                [ button [ class "btn btn-primary", onClick SubmitUserForm ] [ text "Save" ]
                , button [ class "btn btn-outline", onClick CloseUserForm ] [ text "Cancel" ]
                ]
            ]
        )


{-| Self-service password change, available to every signed-in role via the
header button.
-}
passwordModal : Model -> Html Msg
passwordModal model =
    Ui.modal "Change Password"
        (div []
            [ checkedInputField model "pwCurrent" "Current Password" model.pwCurrent "password" PwCurrentChanged
            , checkedInputField model "pwNew" "New Password (min 12 characters)" model.pwNew "password" PwNewChanged
            , checkedInputField model "pwConfirm" "Confirm New Password" model.pwConfirm "password" PwConfirmChanged
            , div [ class "flex", Html.Attributes.style "margin-top" "14px" ]
                [ button [ class "btn btn-primary", onClick SubmitPasswordChange ]
                    [ text "Update Password" ]
                , button [ class "btn btn-outline", onClick TogglePwModal ] [ text "Cancel" ]
                ]
            ]
        )



-- ---------- audit trail ----------


{-| Admin-only "who changed what and when" page.
-}
auditView : Model -> Html Msg
auditView model =
    let
        me_ =
            Maybe.withDefault { id = 0, email = "", name = "", role = "", revision = 1, mfaRequired = False } model.user
    in
    if me_.role /= "admin" then
        div [ class "card" ]
            [ Ui.emptyNote "Admin access required." ]

    else
        let
            actionTag action =
                span
                    [ class
                        (if action == "deleted" then
                            "tag tag-lost"

                         else if action == "created" then
                            "tag tag-converted"

                         else
                            "tag tag-stage-blue"
                        )
                    ]
                    [ text action ]

            entityLink e =
                case entityHref e of
                    Just path ->
                        a [ class "tag tag-id", href path ]
                            [ text (Ui.entityLabel e.entityType ++ " #" ++ String.fromInt e.entityId) ]

                    Nothing ->
                        span [ class "tag tag-id" ] [ text (Ui.entityLabel e.entityType) ]

            auditRow e =
                tr []
                    [ td [] [ text (Ui.fmtDateTime e.createdAt) ]
                    , td [] [ text (Maybe.withDefault "—" e.actorName) ]
                    , td [] [ actionTag e.action ]
                    , td [] [ text (Maybe.withDefault "" e.entityName) ]
                    , td [] [ entityLink e ]
                    , td [] (changeLines e.changes)
                    ]
        in
        div []
            [ div [ class "page-head" ]
                [ div []
                    [ h2 [] [ text "Audit Trail" ]
                    , span [ class "empty-note" ]
                        [ text "Every lead and student edit and deletion, with before/after values." ]
                    ]
                ]
            , div [ class "card table-card" ]
                [ if List.isEmpty model.audit then
                    Ui.emptyNote "No changes recorded yet."

                  else
                    table [ class "data-table" ]
                        [ thead []
                            [ tr []
                                [ th [] [ text "When" ]
                                , th [] [ text "Who" ]
                                , th [] [ text "Action" ]
                                , th [] [ text "Record" ]
                                , th [] [ text "Entity" ]
                                , th [] [ text "Changes" ]
                                ]
                            ]
                        , tbody [] (List.map auditRow model.audit)
                        ]
                ]
            ]


entityHref : AuditEntry -> Maybe String
entityHref e =
    case e.entityType of
        "lead" ->
            Just ("/leads/" ++ String.fromInt e.entityId)

        "client" ->
            Just ("/clients/" ++ String.fromInt e.entityId)

        _ ->
            Nothing


{-| Render the JSONB @{"Field":{"from":…,"to":…}}@ blob as one line per
changed field.
-}
changeLines : Maybe D.Value -> List (Html msg)
changeLines mv =
    case mv of
        Nothing ->
            []

        Just v ->
            case D.decodeValue (D.keyValuePairs changeEntry) v of
                Ok pairs ->
                    List.map
                        (\( field, diff ) ->
                            div [ class "activity-desc" ] [ text (field ++ ": " ++ diff) ]
                        )
                        pairs

                Err _ ->
                    [ div [ class "activity-desc" ] [ text "(unparsable change)" ] ]


changeEntry : D.Decoder String
changeEntry =
    D.map2 (\from to -> from ++ " → " ++ to)
        (D.field "from" auditValueStr)
        (D.field "to" auditValueStr)


auditValueStr : D.Decoder String
auditValueStr =
    D.oneOf
        [ D.string
        , D.null "—"
        , D.map String.fromInt D.int
        , D.map (\b -> if b then "yes" else "no") D.bool
        ]



-- ---------- notifications & toasts ----------


overdueTasks : Model -> List Task
overdueTasks model =
    List.filter
        (\t ->
            t.status /= "Done"
                && t.dueDate
                /= Nothing
                && Maybe.withDefault True (Maybe.map (\d -> d < model.today) t.dueDate)
        )
        model.tasks


dueSoonTasks : Model -> List Task
dueSoonTasks model =
    List.filter
        (\t ->
            t.status /= "Done"
                && t.dueDate
                /= Nothing
                && Maybe.withDefault False
                    (Maybe.map
                        (\d -> d >= model.today && d <= addDaysStr model.today 3)
                        t.dueDate
                    )
        )
        model.tasks


addDaysStr : String -> Int -> String
addDaysStr iso days =
    case Date.fromIsoString iso of
        Ok d ->
            Date.toIsoString (Date.add Date.Days days d)

        Err _ ->
            iso


notificationsDropdown : Model -> Html Msg
notificationsDropdown model =
    let
        overdue =
            overdueTasks model

        dueSoon =
            dueSoonTasks model

        item t suffix =
            div
                [ class "notification-item unread"
                , onClick (NavigateTo (Maybe.map (\id -> "/clients/" ++ String.fromInt id) t.clientId |> Maybe.withDefault ("/leads/" ++ String.fromInt t.leadId)))
                ]
                [ span [ class "notification-icon" ] [ text "⏰" ]
                , div [ class "notification-content" ]
                    [ div [ class "notification-title" ] [ text t.title ]
                    , div [ class "notification-subtitle" ]
                        [ text
                            (suffix
                                ++ " · "
                                ++ Maybe.withDefault "" t.leadName
                            )
                        ]
                    ]
                , span [ class "notification-dot" ] []
                ]
    in
    div [ class "notification-wrapper" ]
        [ button
            [ class
                ("notification-bell "
                    ++ (if not (List.isEmpty overdue) || not (List.isEmpty dueSoon) then
                            "has-notifications"

                        else
                            ""
                       )
                )
            , onClick NotifBellClicked
            ]
            [ text "🔔"
            , if not (List.isEmpty overdue) then
                span [ class "notification-badge" ]
                    [ text (String.fromInt (List.length overdue)) ]

              else
                span [] []
            ]
        , if model.notifOpen then
            div [ class "notification-dropdown" ]
                [ div [ class "notification-header" ]
                    [ text "Notifications" ]
                , div [ class "notification-list" ]
                    (List.map (\t -> item t "Overdue") overdue
                        ++ List.map (\t -> item t "Due soon") dueSoon
                        ++ (if List.isEmpty overdue && List.isEmpty dueSoon then
                                [ div [ class "notification-empty" ]
                                    [ text "Nothing needs your attention 🎉" ]
                                ]

                            else
                                []
                           )
                    )
                ]

          else
            span [] []
        ]


toastStack : Model -> Html Msg
toastStack model =
    if List.isEmpty model.toasts then
        span [] []

    else
        div [ class "toast-container" ]
            (List.map
                (\t ->
                    div
                        [ class
                            ("toast toast-"
                                ++ (case t.kind of
                                        "success" ->
                                            "success"

                                        "error" ->
                                            "error"

                                        _ ->
                                            "info"
                                   )
                            )
                        ]
                        [ text t.msg ]
                )
                model.toasts
            )


isReadOnly : Model -> Bool
isReadOnly model =
    Maybe.map .role model.user == Just "viewer"


checkedInputField : Model -> String -> String -> String -> String -> (String -> Msg) -> Html Msg
checkedInputField model key labelText current kind changed =
    let
        error = Dict.get key model.featureErrors |> Maybe.withDefault ""
        fieldId = "record-field-" ++ key
    in
    div [class "form-group"]
        [ label [Html.Attributes.for fieldId] [text labelText]
        , input [Html.Attributes.id fieldId,class "input",type_ kind,value current,onInput changed,Html.Attributes.attribute "aria-invalid" (if error == "" then "false" else "true"),Html.Attributes.attribute "aria-describedby" (fieldId ++ "-error"),Html.Attributes.attribute "autocomplete" (if kind == "password" then (if key == "pwCurrent" then "current-password" else "new-password") else if kind == "email" then "email" else "off")] []
        , Html.p [Html.Attributes.id (fieldId ++ "-error"),class "field-error",Html.Attributes.attribute "role" "status"] [text error]
        ]


studentContactLinks : Maybe String -> Html Msg
studentContactLinks phone =
    case phone of
        Nothing -> text "Add a phone number to use contact links."
        Just number ->
            let
                digits=String.filter Char.isDigit number
                international=String.startsWith "+" (String.trim number) && String.length digits>=7 && String.length digits<=15
                mobile=if String.startsWith "+" (String.trim number) then "+" ++ digits else digits
            in
            div [class "contact-actions"]
                [ if international then a [class "btn btn-sm btn-outline",href ("https://wa.me/" ++ digits),Html.Attributes.target "_blank",Html.Attributes.rel "noopener noreferrer"] [text "Open WhatsApp"] else text "Use +country code to open WhatsApp."
                , a [class "btn btn-sm btn-outline",href ("sms:" ++ mobile)] [text "Open SMS"]
                , a [class "btn btn-sm btn-outline",href "/work/contact-log"] [text "Log a conversation"]
                , Html.p [class "status-help"] [text "Messages open in your own apps. The CRM does not send them or log them automatically."]
                ]
