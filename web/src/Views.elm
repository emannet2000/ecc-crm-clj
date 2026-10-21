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
        subtitle = if resetting then "Choose a new password for your account." else if recovering then "We’ll email you a secure link to reset your password." else "Sign in to your client workspace."
    in
    div [ class "login-wrap" ]
        [ div [ class "login-story" ]
            [ div [ class "login-brand" ] [ div [ class "logo-icon" ] [ text "E" ], strong [] [ text "ECC" ], span [] [ text "CLIENT WORKSPACE" ] ]
            , div [ class "login-story-copy" ] [ div [ class "eyebrow" ] [ text "BUILT AROUND PEOPLE" ], Html.h1 [] [ text "Every journey.", Html.br [] [], text "A little clearer." ], Html.p [] [ text "Keep your relationships, cases and next steps together. Make every client feel remembered." ] ]
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
                , div [ class "login-hint" ] [ text "Need access? Ask your workspace administrator for an invitation." ]
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
                [ div [ class "stats dashboard-stats" ]
                    [ statCard "leads" "Active leads" (String.fromInt stats.hotLeads ++ " high-priority relationships") (String.fromInt stats.totalLeads) "/leads"
                    , statCard "clients" "Clients" "People you’re helping move forward" (String.fromInt stats.totalClients) "/clients"
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
            [ inputField "Full Name *" f.fullName "text" (\v -> UpdateAddLead (\g -> { g | fullName = v }))
            , inputField "Email" f.email "email" (\v -> UpdateAddLead (\g -> { g | email = v }))
            , inputField "Phone" f.phone "text" (\v -> UpdateAddLead (\g -> { g | phone = v }))
            , selectField "Source" Types.sources f.source (\v -> UpdateAddLead (\g -> { g | source = v }))
            , selectField "Quality" Types.qualities f.quality (\v -> UpdateAddLead (\g -> { g | quality = v }))
            , selectField "Stage" Types.leadStages f.stage (\v -> UpdateAddLead (\g -> { g | stage = v }))
            , selectField "Destination" Types.destinations f.destination (\v -> UpdateAddLead (\g -> { g | destination = v }))
            , selectField "Service" Types.services f.service (\v -> UpdateAddLead (\g -> { g | service = v }))
            , inputField "Next Follow-up" f.nextFollowup "date" (\v -> UpdateAddLead (\g -> { g | nextFollowup = v }))
            , inputField "Notes" f.notes "text" (\v -> UpdateAddLead (\g -> { g | notes = v }))
            , div [ class "flex", Html.Attributes.style "margin-top" "14px" ]
                [ button [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-primary", onClick SubmitAddLead ] [ text "Save Lead" ]
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
                        , button [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-success", onClick (ConfirmRequested "Convert this lead to a client? Documents, tasks and the journey history will be preserved." (ConvertClicked l.id)) ] [ text "Convert to Client" ]
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
        [ inputField "Full Name" f.fullName "text" (\v -> UpdateEditLead (\g -> { g | fullName = v }))
        , inputField "Email" f.email "email" (\v -> UpdateEditLead (\g -> { g | email = v }))
        , inputField "Phone" f.phone "text" (\v -> UpdateEditLead (\g -> { g | phone = v }))
        , selectField "Stage" Types.leadStages f.stage (\v -> UpdateEditLead (\g -> { g | stage = v }))
        , selectField "Quality" Types.qualities f.quality (\v -> UpdateEditLead (\g -> { g | quality = v }))
        , selectField "Source" Types.sources f.source (\v -> UpdateEditLead (\g -> { g | source = v }))
        , selectField "Destination" Types.destinations f.destination (\v -> UpdateEditLead (\g -> { g | destination = v }))
        , selectField "Service" Types.services f.service (\v -> UpdateEditLead (\g -> { g | service = v }))
        , inputField "Last Contact" f.lastContact "date" (\v -> UpdateEditLead (\g -> { g | lastContact = v }))
        , inputField "Next Follow-up" f.nextFollowup "date" (\v -> UpdateEditLead (\g -> { g | nextFollowup = v }))
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
            [ button [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-primary", onClick SubmitEditLead ] [ text "Save Changes" ]
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
            , button [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-sm btn-primary", onClick uploadMsg ]
                [ text "Upload" ]
            ]
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
        , if d.scanStatus/="Clean" then span [class "tag"] [text ("Scan: " ++ d.scanStatus)] else a
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
                , td [] [ text c.number ]
                , td [] [ text (Maybe.withDefault "—" c.phone) ]
                , td [] [ text (Maybe.withDefault "—" c.caseOfficerName) ]
                , td [ class "lead-source" ] [ text (Ui.fmtDateTime c.createdAt) ]
                ]
    in
    div []
        [ div [ class "page-head" ]
            [ h2 [] [ text "Clients" ]
            , div [ class "flex" ]
                [ a
                    [ class "btn btn-outline"
                    , href (Api.exportCsvUrl
                                { base = model.apiBase, token = model.token }
                                "clients")
                    , Html.Attributes.download ""
                    ]
                    [ text "Export CSV" ]
                , button [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-primary", onClick OpenAddClient ] [ text "+ Add Client" ]
                ]
            ]
        , div [ class "search-container" ]
            [ div [ class "search-row" ]
                [ div [ class "search-input-wrapper" ]
                    [ input
                        [ class "search-input"
                        , Html.Attributes.attribute "aria-label" "Search clients"
                        , placeholder "Search clients…"
                        , value model.clientQ
                        , onInput ClientSearchChanged
                        ]
                        []
                    ]
                ]
            ]
        , div [ class "card table-card", Html.Attributes.style "margin-top" "12px" ]
            [ if List.isEmpty visible then
                Ui.emptyState "clients" "No clients to show" "Try another search, add a client, or convert a qualified lead."

              else
                table [ class "data-table clients-table" ]
                    [ thead []
                        [ tr []
                            [ th [] [ text "Client" ]
                            , th [] [ text "Number" ]
                            , th [] [ text "Phone" ]
                            , th [] [ text "Case Officer" ]
                            , th [] [ text "Since" ]
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
                    "Edit Client"

                Nothing ->
                    "Add Client"
    in
    Ui.modal title
        (div []
            [ inputField "Full Name *" f.fullName "text" (\v -> UpdateClientForm (\g -> { g | fullName = v }))
            , inputField "Email" f.email "email" (\v -> UpdateClientForm (\g -> { g | email = v }))
            , inputField "Phone" f.phone "text" (\v -> UpdateClientForm (\g -> { g | phone = v }))
            , div [ class "form-group" ]
                [ label [] [ text "Case Officer" ]
                , select
                    [ onInput (\v -> UpdateClientForm (\g -> { g | officerId = v })) ]
                    (option [ value "" ] [ text "— none —" ]
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
                [ button [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-primary", onClick SubmitClientForm ] [ text "Save" ]
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
                        [ td [] [ text (Maybe.withDefault "—" cr.category) ]
                        , td [] [ text (Maybe.withDefault "—" cr.destination) ]
                        , td [] [ span [ class "tag tag-stage-blue" ] [ text cr.stage ] ]
                        , td [] [ text (Ui.fmtDate cr.deadline) ]
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
            div []
                [ a [ class "back-link", href "#", onClick (NavigateTo "/clients") ] [ text "← Back to Clients" ]
                , div [ class "page-head" ]
                    [ div []
                        [ h2 [] [ text c.fullName ]
                        , div [ class "lead-detail-badges" ]
                            [ span [ class "tag tag-id" ] [ text c.number ]
                            ]
                        ]
                    , div [ class "flex" ]
                        [ button [ Html.Attributes.disabled (isReadOnly model),  class "btn", onClick (OpenCaseForm Nothing) ] [ text "+ Add Case" ]
                        , button
                            [ Html.Attributes.disabled (isReadOnly model),  class "btn"
                            , onClick (OpenClientEditor c.id)
                            ]
                            [ text "Edit" ]
                        , button [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-danger", onClick (ConfirmRequested "Move this client to the archive? Its cases, documents and history will be preserved." (DeleteClientConfirmed c.id)) ] [ text "Delete" ]
                        ]
                    ]
                , div [ class "detail-grid" ]
                    [ div [ class "card" ]
                        [ div [ class "section-head" ] [ h3 [] [ text "Details" ] ]
                        , div [ class "kv-grid" ]
                            [ div [ class "kv" ] [ div [] [ text "Email" ], div [] [ text (Maybe.withDefault "—" c.email) ] ]
                            , div [ class "kv" ] [ div [] [ text "Phone" ], div [] [ text (Maybe.withDefault "—" c.phone) ] ]
                            , div [ class "kv" ] [ div [] [ text "Case Officer" ], div [] [ text (Maybe.withDefault "—" c.caseOfficerName) ] ]
                            , div [ class "kv" ] [ div [] [ text "Since" ], div [] [ text (Ui.fmtDateTime c.createdAt) ] ]
                            ]
                        ]
                    , div [ class "card table-card" ]
                        [ div [ class "section-head" ] [ h3 [] [ text "Cases" ] ]
                        , if List.isEmpty cd.cases then
                            Ui.emptyNote "No cases yet — add one."

                          else
                            table [ class "data-table" ]
                                [ thead []
                                    [ tr []
                                        [ th [] [ text "Service" ]
                                        , th [] [ text "Destination" ]
                                        , th [] [ text "Stage" ]
                                        , th [] [ text "Deadline" ]
                                        , th [] []
                                        , th [] []
                                        ]
                                    ]
                                , tbody [] (List.map caseRow cd.cases)
                                ]
                        ]
                    ]
                , div [ class "detail-grid", Html.Attributes.style "margin-top" "16px" ]
                    [ documentsCard model cd.documents (UploadClientDocClicked cd.client.id)
                    , div [ class "card" ] [ div [ class "section-head" ] [ h3 [] [ text "Tasks & follow-ups" ], button [ class "btn btn-sm btn-outline", onClick (NavigateTo "/tasks") ] [ text "Manage tasks ↗" ] ], taskComposer model (SubmitClientTask cd.client.id), taskRows model cd.tasks ]
                    , div [ class "card" ] [ h3 [] [ text "Journey history" ], if List.isEmpty cd.activities then Ui.emptyNote "Activity will appear here as the relationship grows." else div [] (List.map (\activity -> div [ class "activity-item" ] [ span [ class "activity-date" ] [ text activity.date ], text (Maybe.withDefault "" activity.description) ]) cd.activities) ]
                    ]
                , Features.embedded model cid
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
            "Add Case"

         else
            "Edit Case"
        )
        (div []
            [ selectField "Service Category" Types.services cf.category
                (\v -> UpdateCaseForm (\f -> { f | category = v }))
            , selectField "Destination" Types.destinations cf.destination
                (\v -> UpdateCaseForm (\f -> { f | destination = v }))
            , selectField "Stage" Types.caseStages cf.stage
                (\v -> UpdateCaseForm (\f -> { f | stage = v }))
            , inputField "Next Deadline" cf.deadline "date"
                (\v -> UpdateCaseForm (\f -> { f | deadline = v }))
            , div [ class "flex", Html.Attributes.style "margin-top" "14px" ]
                [ button [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-primary", onClick (SubmitCaseForm cd.client.id) ] [ text "Save Case" ]
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
                                        , href "#"
                                        , onClick (NavigateTo (Maybe.map (\id -> "/clients/" ++ String.fromInt id) t.clientId |> Maybe.withDefault ("/leads/" ++ String.fromInt t.leadId)))
                                        ]
                                        [ text (Maybe.withDefault "" t.leadName) ]
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
        , div [ class "task-board" ]
            [ section "Pending"
            , section "In Progress"
            , section "Done"
            ]
        ]


globalAddTaskForm : Model -> Html Msg
globalAddTaskForm model =
    div [ class "card", Html.Attributes.style "margin-bottom" "16px" ]
        [ div [ class "inline-form" ]
            [ div [ class "form-group", Html.Attributes.style "flex" "1.5" ]
                [ label [] [ text "Lead or client" ]
                , select
                    [ onInput (\v -> UpdateAddTask (\f -> { f | leadId = v })) ]
                    (option [ value "" ] [ text "Choose a lead or client…" ]
                        :: List.map
                            (\l ->
                                option
                                    [ value (String.fromInt l.id)
                                    , selected (model.addTask.leadId == String.fromInt l.id)
                                    ]
                                    [ text (l.number ++ " — " ++ l.fullName) ]
                            )
                            model.leads
                        ++ List.map (\client -> option [ value ("client:" ++ String.fromInt client.id), selected (model.addTask.leadId == "client:" ++ String.fromInt client.id) ] [ text ("Client · " ++ client.fullName) ]) model.clients
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
            , button [ Html.Attributes.disabled (isReadOnly model),  class "btn btn-primary", onClick SubmitAddTaskGlobal ] [ text "Create" ]
            ]
        ]



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
                        [ text "Admins manage accounts. Viewers are read-only." ]
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
                inputField "Password (leave blank to keep current)" f.password "password"
                    (\v -> UpdateUserForm (\g -> { g | password = v }))

            else
                inputField "Password (12+ characters, or leave blank to email an invitation)" f.password "password"
                    (\v -> UpdateUserForm (\g -> { g | password = v }))
    in
    Ui.modal
        (if editing then
            "Edit User"

         else
            "Add User"
        )
        (div []
            [ inputField "Full Name" f.name "text"
                (\v -> UpdateUserForm (\g -> { g | name = v }))
            , if editing then
                div [ class "form-group" ]
                    [ label [] [ text "Email" ]
                    , div [ class "input", Html.Attributes.style "color" "#5B6572" ]
                        [ text f.email ]
                    ]

              else
                inputField "Email" f.email "email"
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
            [ inputField "Current Password" model.pwCurrent "password" PwCurrentChanged
            , inputField "New Password (min 12 characters)" model.pwNew "password" PwNewChanged
            , inputField "Confirm New Password" model.pwConfirm "password" PwConfirmChanged
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
                            [ text (e.entityType ++ " #" ++ String.fromInt e.entityId) ]

                    Nothing ->
                        span [ class "tag tag-id" ] [ text e.entityType ]

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
                        [ text "Every lead and client edit and deletion, with before/after values." ]
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
