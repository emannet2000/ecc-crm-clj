port module Main exposing (main)

{-| ECC CRM — Elm frontend entry point.

Routing, authentication flow, data loading, and the update loop live here;
page markup lives in Views.elm.
-}

import Browser
import Browser.Navigation as Nav
import Date
import Html exposing (Html, a, button, div, span, strong, text)
import Html.Attributes exposing (class, href)
import Html.Events exposing (onClick)
import Http
import Json.Encode as E
import Process
import Task
import Time
import Url
import Url exposing (Url)
import Set exposing (Set)

import Api
import State exposing (..)
import Types
import Ui
import Views
import Features
import Dict
import Operations
import Json.Decode as D


main : Program () Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , onUrlRequest = LinkClicked
        , onUrlChange = UrlChanged
        }



-- ---------- ports ----------


port saveToken : Maybe String -> Cmd msg
port loadToken : (Maybe String -> msg) -> Sub msg
port saveDark : Bool -> Cmd msg
port loadDark : (Bool -> msg) -> Sub msg



-- ---------- init ----------


init : () -> Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    let
        proto =
            case url.protocol of
                Url.Http ->
                    "http"

                Url.Https ->
                    "https"

        base =
            Api.computeBase { protocol = proto, host = url.host, port_ = url.port_ }
    in
    ( State.initialModel key url |> (\m -> { m | apiBase = base, featureForm = Features.defaults (String.dropLeft 6 url.path) })
    , Cmd.batch
        [ Task.perform (TodayChanged << toIsoDay) Time.now
        , if url.path == "/portal" then
            case url.fragment of
                Just fragment -> Task.perform (always (PortalExchange (String.dropLeft 6 fragment))) (Task.succeed ())
                Nothing -> Api.portalGet { base = base, token = Nothing } (acceptLoad (State.initialModel key url) PortalLoaded)
          else Cmd.none
        ]
    )


toIsoDay : Time.Posix -> String
toIsoDay posix =
    Date.toIsoString (Date.fromPosix Time.utc posix)


-- ---------- routing helpers ----------


routeCmd : Model -> Route -> Cmd Msg
routeCmd model route =
    let
        ctx =
            { base = model.apiBase, token = model.token }

        alwaysFetch =
            Cmd.batch
                [ Api.fetchTasksPage ctx model.pageOffset (acceptLoad model TasksLoaded)
                ]
    in
    case route of
        Dashboard ->
            Cmd.batch
                [ Api.fetchStats ctx (acceptLoad model StatsLoaded)
                , Api.fetchLeads ctx (acceptLoad model LeadsLoaded)
                ]

        LeadsPage ->
            Cmd.batch
                [ Api.fetchFilteredLeads ctx model model.pageOffset (acceptLoad model LeadsLoaded)
                , Api.fetchUsers ctx (acceptLoad model UsersLoaded)
                ]

        LeadDetailPage id ->
            Cmd.batch
                [ Api.fetchLeadDetail ctx id (acceptLoad model DetailLoaded)
                , Api.fetchUsers ctx (acceptLoad model UsersLoaded)
                ]

        ClientsPage ->
            Cmd.batch
                [ Api.fetchClientsPage ctx model.pageOffset model.clientQ (acceptLoad model ClientsLoaded)
                , Api.fetchUsers ctx (acceptLoad model UsersLoaded)
                ]

        ClientDetailPage id ->
            Cmd.batch
                [ Api.fetchClientDetail ctx id (acceptLoad model ClientDetailLoaded)
                , Api.featureGet ctx (inlinePath model id) model.featureSearch model.pageOffset (acceptLoad model FeatureLoaded)
                , Api.fetchUsers ctx (acceptLoad model UsersLoaded)
                ]

        TasksPage ->
            Cmd.batch
                [ Api.fetchTasksPage ctx model.pageOffset (acceptLoad model TasksLoaded)
                , Api.fetchLeads ctx (acceptLoad model LeadsLoaded)
                , Api.fetchClients ctx (acceptLoad model ClientsLoaded)
                ]

        UsersPage ->
            Api.fetchUsers ctx (acceptLoad model UsersLoaded)

        AuditPage ->
            Api.fetchAudit ctx 200 (acceptLoad model AuditLoaded)

        WorkspacePage kind ->
            if String.startsWith "work/" kind then
                Api.featureGet ctx (String.dropLeft 5 kind) model.featureSearch model.pageOffset (acceptLoad model FeatureLoaded)
            else
                Api.fetchOperations ctx kind model.pageOffset (acceptLoad model OperationsLoaded)



-- ---------- update ----------


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        AcceptLoad key loaded ->
            if key == loadKeyFor loaded model then
                update loaded model
            else
                ( model, Cmd.none )

        _ ->
            if expiredSession msg then
                ( { model | user = Nothing, token = Nothing, authChecked = True, loadEpoch = model.loadEpoch + 1, userEpoch = model.userEpoch + 1, loginError = "Your session has expired. Please sign in again.", loginPassword = "", loginOtp = "", featureData = E.null, featureResult = E.null, featureForm = Dict.empty, portalData = E.null, portalFile = Nothing, conflictCurrent = E.null, featureBaseline = Dict.empty, conflictOriginal = Dict.empty, conflictEdits = Dict.empty, recordBaseline = E.null, checklistFile = Nothing, featureBusy = False, detail = Nothing, clientDetail = Nothing, leads = [], clients = [], tasks = [], users = [], opsData = [], audit = [] }, saveToken Nothing )
            else
                updateHelp msg { model | loadEpoch = model.loadEpoch + (if startsLoad msg then 1 else 0), userEpoch = model.userEpoch + (if startsUserLoad msg then 1 else 0) }


acceptLoad : Model -> (a -> Msg) -> a -> Msg
acceptLoad model constructor result =
    let loaded = constructor result in
    AcceptLoad (loadKeyFor loaded model) loaded


loadKeyFor : Msg -> Model -> String
loadKeyFor msg model =
    case msg of
        UsersLoaded _ -> E.encode 0 (E.list E.string [ Maybe.withDefault "" model.token, String.fromInt model.userEpoch ])
        _ -> loadKey model


startsUserLoad : Msg -> Bool
startsUserLoad msg =
    case msg of
        UserSaved (Ok _) -> True
        UserUpdatedDone (Ok _) -> True
        DeleteUserDone (Ok _) -> True
        LogoutClicked -> True
        LogoutDone (Ok _) -> True
        PasswordChangeDone (Ok _) -> True
        UrlChanged _ -> True
        _ -> False


loadKey : Model -> String
loadKey model =
    E.encode 0 (E.list E.string
        [ model.url.path, Maybe.withDefault "" model.token, String.fromInt model.loadEpoch, String.fromInt model.pageOffset
        , model.q, model.clientQ, model.fStage, model.fQuality, model.fSource
        , model.sortBy, model.inlineSection, model.inlineOwner, model.featureSearch, if model.sortAsc then "asc" else "desc"
        ])


startsLoad : Msg -> Bool
startsLoad msg =
    case msg of
        UrlChanged _ -> True
        PageStep _ -> True
        SearchReady _ _ -> True
        FeatureEdit _ -> True
        FeatureReset -> True
        InlineSection _ -> True
        InlineOwner _ -> True
        FeatureSearch _ -> True
        PortalExchange _ -> True
        PortalUpload _ -> True
        PortalLogout -> True
        PortalUploaded (Ok _) -> True
        FeatureDone (Ok _) -> True
        SearchChanged _ -> True
        ClientSearchChanged _ -> True
        StageFilterChanged _ -> True
        QualityFilterChanged _ -> True
        SourceFilterChanged _ -> True
        SortByChanged _ -> True
        SortDirToggled -> True
        ClearFilters -> True
        LogoutClicked -> True
        LogoutDone (Ok _) -> True
        PasswordChangeDone (Ok _) -> True
        NavigateTo _ -> True
        OperationDone (Ok _) -> True
        AddLeadDone (Ok _) -> True
        EditLeadDone (Ok _) -> True
        DeleteLeadDone (Ok _) -> True
        AdvanceDone (Ok _) -> True
        ConvertDone (Ok _) -> True
        NoteDone (Ok _) -> True
        BulkDone (Ok _) -> True
        TaskStatusDone (Ok _) -> True
        TaskDeleteDone (Ok _) -> True
        AddTaskDone (Ok _) -> True
        ClientUpdated (Ok _) -> True
        ClientFormSaved (Ok _) -> True
        DeleteClientDone (Ok _) -> True
        CaseFormSaved (Ok _) -> True
        DeleteCaseDone (Ok _) -> True
        LeadDocUploaded (Ok _) -> True
        ClientDocUploaded (Ok _) -> True
        DocDeleteDone (Ok _) -> True
        LeadsImported (Ok _) -> True
        UserSaved (Ok _) -> True
        UserUpdatedDone (Ok _) -> True
        DeleteUserDone (Ok _) -> True
        _ -> False


updateHelp : Msg -> Model -> ( Model, Cmd Msg )
updateHelp msg model =
    let
        ctx =
            { base = model.apiBase, token = model.token }
    in
    case msg of
        ConfirmRequested message action ->
            ( { model | confirmation = Just ( message, action ) }, Cmd.none )

        ConfirmDismissed ->
            ( { model | confirmation = Nothing }, Cmd.none )

        ConfirmAccepted ->
            case model.confirmation of
                Just ( _, action ) -> update action { model | confirmation = Nothing }
                Nothing -> ( model, Cmd.none )

        AcceptLoad _ _ ->
            ( model, Cmd.none )

        LoginOtpChanged value ->
            ( { model | loginOtp = value }, Cmd.none )

        FeatureLoaded result ->
            case result of
                Ok value ->
                    let pref = D.decodeValue (D.field "security" D.value) value |> Result.withDefault E.null |> Features.rowForm |> Dict.map (\key v -> if List.member key ["assignments","deadlines","documents","escalations","emailEnabled"] then (if v=="1" || v=="true" then "true" else "false") else v) in
                    ( { model | featureForm = if featureSection model=="notifications" then Dict.union pref model.featureForm else if model.inlineOwner/="" && Dict.get "owner" model.featureForm==Nothing then Dict.insert "owner" model.inlineOwner model.featureForm else model.featureForm, featureData = value, opsData = D.decodeValue (D.field "rows" (D.list D.value)) value |> Result.withDefault [], pageLoading = False, pageError = "" }, Cmd.none )
                Err err -> ( { model | pageLoading = False, pageError = httpError err }, Cmd.none )

        InlineSection section ->
            let next = { model | inlineSection = section, featureForm = Dict.insert "owner" model.inlineOwner (Features.defaults section), featureSearch = "", featureResult = E.null, featureError = "", pageOffset = 0, featureBusy = False, checklistFile = Nothing } in
            ( next, reloadCurrent next )

        InlineOwner own ->
            let next = { model | inlineOwner = own, featureForm = Dict.insert "owner" own (Features.defaults model.inlineSection), featureSearch = "", pageOffset = 0, featureResult = E.null, featureError = "", featureBusy = False } in
            ( next, reloadCurrent next )

        ChecklistFile file -> ( { model | checklistFile = Just file }, Cmd.none )

        ChecklistUpload rid revision ->
            case model.checklistFile of
                Just file ->
                    if model.featureBusy then ( model, Cmd.none ) else
                    ( { model | featureBusy = True, featureError = "", featureForm = Dict.insert "id" (String.fromInt rid) model.featureForm }, Api.checklistUpload ctx rid revision file (acceptLoad model FeatureDone) )
                Nothing -> ( { model | featureError = "Choose a file to upload." }, Cmd.none )

        ConflictLoaded result ->
            case result of
                Ok current -> ( { model | conflictCurrent = current }, Cmd.none )
                Err err -> ( { model | featureError = httpError err }, toast "error" (httpError err) )

        ConflictDismiss -> ( { model | conflictCurrent = E.null }, Cmd.none )

        ConflictUseCurrent key ->
            let latest = Features.formValues model.conflictCurrent |> Dict.get key |> Maybe.withDefault "" in
            ( { model | featureForm = Dict.insert key latest model.featureForm, conflictEdits = Dict.insert key latest model.conflictEdits }, Cmd.none )

        ConflictRebase ->
            let
                revision = D.decodeValue (D.field "revision" D.int) model.conflictCurrent |> Result.withDefault 0
                cf = model.clientForm
                ef = model.editLead
                uf = model.userForm
            in
            ( { model | conflictCurrent = E.null, recordBaseline = model.conflictCurrent, featureForm = Dict.insert "expectedRevision" (String.fromInt revision) model.featureForm, featureBaseline = Features.formValues model.conflictCurrent, clientForm = { cf | revision = if model.conflictKind == "clients" then revision else cf.revision }, editLead = { ef | revision = if model.conflictKind == "leads" then revision else ef.revision }, userForm = { uf | revision = if model.conflictKind == "users" then revision else uf.revision }, caseForm = Maybe.map (\f -> { f | revision = if model.conflictKind == "cases" then revision else f.revision }) model.caseForm, featureError = "Comparison accepted. Review your form and save when ready." }, Cmd.none )

        FeatureField key value ->
            ( { model | featureForm = Dict.insert key value model.featureForm }, Cmd.none )

        FeatureSearch query ->
            let next = { model | featureSearch = query, pageOffset = 0, pageLoading = True } in
            ( next, reloadCurrent next )

        FeatureEdit row ->
            ( { model | featureForm = Dict.union (Features.rowForm row) (Dict.insert "owner" model.inlineOwner (Features.defaults (featureSection model))), featureBaseline = Features.formValues row, conflictCurrent = E.null, featureBusy = False, featureResult = E.null, featureError = "" }, Cmd.none )

        FeatureReset ->
            let next = { model | featureForm = Dict.insert "owner" model.inlineOwner (Features.defaults (featureSection model)), featureResult = E.null, featureError = "", featureBusy = False, conflictCurrent = E.null } in
            ( next, reloadCurrent next )

        FeatureRun action ->
            if model.featureBusy then ( model, Cmd.none ) else if action == "apply" && featureSection model == "search" then
                let next = { model | featureSearch = "@view:" ++ Maybe.withDefault "" (Dict.get "id" model.featureForm), pageOffset = 0, pageLoading = True, featureResult = E.null } in
                ( next, reloadCurrent next )
            else if action == "range" then
                let next = { model | featureSearch = Maybe.withDefault "" (Dict.get "from" model.featureForm) ++ "," ++ Maybe.withDefault "" (Dict.get "to" model.featureForm), pageLoading = True } in
                ( next, reloadCurrent next )
            else
                ( { model | featureBusy = True, featureError = "" }, Api.featurePost ctx (featureSection model ++ "/" ++ action) (E.object (Dict.toList (if model.inlineOwner/="" && (Dict.get "owner" model.featureForm |> Maybe.withDefault "")=="" then Dict.insert "owner" model.inlineOwner model.featureForm else model.featureForm) |> List.map (Tuple.mapSecond E.string))) (acceptLoad model FeatureDone) )

        FeatureDone result ->
            case result of
                Ok value ->
                    let
                        addRevision key fields =
                            case D.decodeValue (D.field key D.int) value of
                                Ok n -> Dict.insert key (String.fromInt n) fields
                                Err _ -> fields
                        form = List.foldl addRevision model.featureForm ["sourceRevision","targetRevision"]
                    in
                    ( { model | featureBusy = False, featureError = "", checklistFile = Nothing, featureResult = value, featureForm = Dict.remove "password" (Dict.remove "code" form) }, reloadCurrent model )
                Err (Http.BadStatus 409) ->
                    if not (List.member (featureSection model) ["tasks","documents","reminders","appointments","invoices","notifications"]) then
                        ( { model | featureBusy = False, featureError = "This action is unavailable in its current state. Refresh or preview the latest records. Email retries require an exhausted failure, no active send, and fewer than three manual retries spaced 15 minutes apart." }, Cmd.none )
                    else
                    let rid = Dict.get (if featureSection model=="reminders" then "task" else "id") model.featureForm |> Maybe.andThen String.toInt |> Maybe.withDefault 0 in
                    beginConflict { model | featureBusy = False, featureError = "The item changed. Compare the current version below." } (featureSection model) rid (dictValue model.featureBaseline) (dictValue model.featureForm)
                Err err -> ( { model | featureBusy = False, featureError = httpError err }, toast "error" (httpError err) )

        PortalExchange token ->
            ( model, Api.portalPost ctx "exchange" (E.object [("token",E.string token)]) PortalExchanged )

        PortalExchanged result ->
            case result of
                Ok _ -> ( { model | portalError = "" }, Nav.replaceUrl model.key "/portal" )
                Err err -> ( { model | portalError = httpError err }, Nav.replaceUrl model.key "/portal" )

        PortalLoaded result ->
            case result of
                Ok value -> ( { model | portalData = value, portalError = "" }, Cmd.none )
                Err err -> ( { model | portalError = httpError err, portalData = E.null }, Cmd.none )

        PortalFile file -> ( { model | portalFile = Just file }, Cmd.none )

        PortalUpload rid ->
            case model.portalFile of
                Just file -> ( model, Api.portalUpload ctx rid file (acceptLoad model PortalUploaded) )
                Nothing -> ( model, Cmd.none )

        PortalUploaded result ->
            case result of
                Ok _ -> ( { model | portalFile = Nothing }, Api.portalGet ctx (acceptLoad model PortalLoaded) )
                Err err -> ( { model | portalError = httpError err }, Cmd.none )

        PortalLogout ->
            ( { model | portalData = E.null, portalFile = Nothing, portalError = "Signed out" }, Api.portalPost ctx "logout" (E.object []) (\_ -> NoOp) )

        LoginModeChanged mode ->
            ( { model | loginMode = mode, loginError = "", loginNotice = "", loginPassword = "" }, Cmd.none )

        RecoverClicked ->
            ( { model | loginBusy = True, loginError = "" }, Api.recover ctx model.loginEmail RecoveryDone )

        ResetClicked ->
            let resetToken = Maybe.withDefault "" model.url.query |> String.dropLeft 6 |> Url.percentDecode |> Maybe.withDefault "" in
            ( { model | loginBusy = True, loginError = "" }, Api.resetPassword ctx resetToken model.loginPassword ResetDone )

        RecoveryDone result ->
            case result of
                Ok _ -> ( { model | loginBusy = False, loginNotice = "If your account exists, you’ll receive an email with a link that expires in one hour." }, Cmd.none )
                Err err -> ( { model | loginBusy = False, loginError = httpError err }, Cmd.none )

        ResetDone result ->
            case result of
                Ok _ -> ( { model | loginBusy = False, loginMode = "login", loginPassword = "", loginNotice = "Password updated. Sign in with your new password." }, Nav.replaceUrl model.key "/" )
                Err err -> ( { model | loginBusy = False, loginError = httpError err }, Cmd.none )

        LogoutDone result ->
            case result of
                Ok _ -> ( { model | user = Nothing, token = Nothing, authChecked = True, loginPassword = "", loginOtp = "", featureData = E.null, featureResult = E.null, featureForm = Dict.empty, portalData = E.null, portalFile = Nothing, conflictCurrent = E.null, featureBaseline = Dict.empty, conflictOriginal = Dict.empty, conflictEdits = Dict.empty, recordBaseline = E.null, checklistFile = Nothing, featureBusy = False, detail = Nothing, clientDetail = Nothing, leads = [], clients = [], tasks = [], users = [], audit = [], opsData = [] }, Cmd.batch [ saveToken Nothing, Nav.pushUrl model.key "/" ] )
                Err err -> ( model, toast "error" (httpError err) )

        PageStep step ->
            let next = { model | pageOffset = max 0 (model.pageOffset + step * 50), pageLoading = True, selected = Set.empty } in
            ( next, routeCmd next (State.routeOf model.url) )

        SearchReady kind query ->
            if (kind == "leads" && query == model.q) || (kind == "clients" && query == model.clientQ) then
                ( { model | pageLoading = True }, if kind == "leads" then Api.fetchFilteredLeads ctx model 0 (acceptLoad model LeadsLoaded) else Api.fetchClientsPage ctx 0 query (acceptLoad model ClientsLoaded) )
            else
                ( model, Cmd.none )

        OperationsLoaded result ->
            ( { model | opsData = Result.withDefault [] result, pageLoading = False, pageError = resultError result }, Cmd.none )

        RunOperation path ->
            ( model, Api.operation ctx path OperationDone )

        OperationDone result ->
            case result of
                Ok _ -> ( model, Cmd.batch [ toast "success" "Saved successfully", reloadCurrent model ] )
                Err err -> ( model, toast "error" (httpError err) )

        NoOp ->
            ( model, Cmd.none )

        LinkClicked request ->
            case request of
                Browser.Internal url ->
                    ( model, Nav.pushUrl model.key (Url.toString url) )

                Browser.External href ->
                    ( model, Nav.load href )

        UrlChanged url ->
            ( { model
                | url = url
                , featureSearch = ""
                , featureForm = Features.defaults (String.dropLeft 6 url.path)
                , featureResult = E.null
                , pageOffset = 0
                , selected = Set.empty
                , pageLoading = True
                , pageError = ""
                , opsData = []
                , inlineOwner = ownerForUrl url
                , featureBaseline = Dict.empty
                , conflictCurrent = E.null
                , checklistFile = Nothing
                , featureBusy = False
                , featureError = ""
                , notifOpen = False
                , detail = Nothing
                , clientDetail = Nothing
                , pendingDoc = Nothing
                , pendingImport = Nothing
              }
            , if url.path == "/portal" then
                case url.fragment of
                    Just fragment -> Task.perform (always (PortalExchange (String.dropLeft 6 fragment))) (Task.succeed ())
                    Nothing -> Api.portalGet ctx (acceptLoad { model | url = url, featureSearch = "", pageOffset = 0 } PortalLoaded)

              else if model.user == Nothing then
                Cmd.none

              else
                routeCmd { model | url = url, pageOffset = 0, featureSearch = "" } (State.routeOf url)
            )

        GotStoredToken t ->
            if t == Nothing then
                ( { model | authChecked = True }, Cmd.none )

            else
                ( { model | token = t }, Api.me { base = model.apiBase, token = t } MeDone )

        GotStoredDark flag ->
            ( { model | darkMode = flag }, Cmd.none )

        ToggleDarkMode ->
            let
                newFlag =
                    not model.darkMode
            in
            ( { model | darkMode = newFlag }, saveDark newFlag )

        TodayChanged iso ->
            ( { model | today = iso }, Cmd.none )

        -- ----- auth -----
        LoginEmailChanged v ->
            ( { model | loginEmail = v, loginError = "" }, Cmd.none )

        LoginPasswordChanged v ->
            ( { model | loginPassword = v, loginError = "" }, Cmd.none )

        LoginClicked ->
            ( { model | loginBusy = True, loginError = "" }
            , Api.login ctx model.loginEmail model.loginPassword model.loginOtp LoginDone
            )

        LoginDone (Ok resp) ->
            ( { model
                | token = Just resp.token
                , authChecked = True
                , loginBusy = False
                , loginPassword = ""
                , loginOtp = ""
                , user = Just resp.user
                , loginError = ""
              }
            , Cmd.batch
                [ saveToken (Just resp.token)
                , toast "success" ("Welcome back, " ++ resp.user.name)
                , if resp.user.mfaRequired then Nav.pushUrl model.key "/work/security" else routeCmd { model | token = Just resp.token } (State.routeOf model.url)
                ]
            )

        LoginDone (Err e) ->
            ( { model | loginError = if e == Http.BadStatus 401 then "Check your email, password, and authenticator or recovery code." else httpError e, loginBusy = False }, Cmd.none )

        MeDone (Ok u) ->
            ( { model | user = Just u, authChecked = True }
            , if u.mfaRequired then Nav.pushUrl model.key "/work/security" else routeCmd model (State.routeOf model.url)
            )

        MeDone (Err e) ->
            ( { model | user = Nothing, authChecked = True, token = Nothing }
            , saveToken Nothing
            )

        LogoutClicked ->
            ( model, Api.logout ctx LogoutDone )

        -- ----- data loads -----
        LeadsLoaded result ->
            ( { model | leads = Result.withDefault model.leads result, pageLoading = False, pageError = resultError result }, Cmd.none )

        UsersLoaded result ->
            ( { model | users = Result.withDefault model.users result, pageLoading = False, pageError = resultError result }, Cmd.none )

        TasksLoaded result ->
            ( { model | tasks = Result.withDefault model.tasks result, pageLoading = False, pageError = resultError result }, Cmd.none )

        ClientsLoaded result ->
            ( { model | clients = Result.withDefault model.clients result, pageLoading = False, pageError = resultError result }, Cmd.none )

        ClientDetailLoaded result ->
            ( { model | clientDetail = justOf result, pageLoading = False, pageError = resultError result }, Cmd.none )

        DetailLoaded result ->
            ( { model | detail = justOf result, pageLoading = False, pageError = resultError result }, Cmd.none )

        StatsLoaded result ->
            ( { model | stats = justOf result, pageLoading = False, pageError = resultError result }, Cmd.none )

        AuditLoaded result ->
            ( { model | audit = Result.withDefault model.audit result }
            , Cmd.none
            )

        -- ----- lead CRUD -----
        OpenAddLead ->
            ( { model | showAddLead = True, addLead = State.emptyAddLead }, Cmd.none )

        CloseAddLead ->
            ( { model | showAddLead = False }, Cmd.none )

        UpdateAddLead f ->
            ( { model | addLead = f model.addLead }, Cmd.none )

        SubmitAddLead ->
            ( model
            , Api.createLead ctx (Types.encodeNewLead model.addLead) AddLeadDone
            )

        AddLeadDone (Ok lead) ->
            ( { model | showAddLead = False, leads = lead :: model.leads }
            , Cmd.batch
                [ toast "success" ("Lead " ++ lead.number ++ " created")
                , navigateTo model.key "/leads"
                ]
            )

        AddLeadDone (Err e) ->
            ( model, toast "error" (httpError e) )

        EditLeadToggled ->
            case model.detail of
                Nothing ->
                    ( model, Cmd.none )

                Just d ->
                    ( { model
                        | editLeadOpen = not model.editLeadOpen
                        , editLead = State.editLeadOf d.lead
                        , recordBaseline = Types.encodeUpdateLead (State.editLeadOf d.lead)
                      }
                    , Cmd.none
                    )

        UpdateEditLead f ->
            ( { model | editLead = f model.editLead }, Cmd.none )

        SubmitEditLead ->
            case model.detail of
                Nothing ->
                    ( model, Cmd.none )

                Just d ->
                    ( model
                    , Api.updateLead ctx d.lead.id (Types.encodeUpdateLead model.editLead) EditLeadDone
                    )

        EditLeadDone (Ok lead) ->
            ( { model | editLeadOpen = False }
            , Cmd.batch
                [ toast "success" "Lead updated"
                  -- refresh detail + list quietly
                , reloadCurrent model
                ]
            )

        EditLeadDone (Err (Http.BadStatus 409)) ->
            beginConflict model "leads" (Maybe.map (.lead >> .id) model.detail |> Maybe.withDefault 0) model.recordBaseline (Types.encodeUpdateLead model.editLead)

        EditLeadDone (Err e) ->
            ( model, toast "error" (httpError e) )

        DeleteLeadConfirmed id ->
            ( model, Api.deleteLead ctx id DeleteLeadDone )

        DeleteLeadDone (Ok _) ->
            ( model
            , Cmd.batch [ toast "success" "Lead deleted", navigateTo model.key "/leads" ]
            )

        DeleteLeadDone (Err e) ->
            ( model, toast "error" (httpError e) )

        AdvanceClicked id ->
            ( model, Api.advanceLead ctx id AdvanceDone )

        AdvanceDone (Ok lead) ->
            ( model
            , Cmd.batch
                [ toast "success" ("Advanced to " ++ lead.stage)
                , reloadCurrent model
                ]
            )

        AdvanceDone (Err e) ->
            ( model, toast "error" (httpError e) )

        ConvertClicked id ->
            ( model, Api.convertLead ctx id ConvertDone )

        ConvertDone (Ok client) ->
            ( model
            , Cmd.batch
                [ toast "success" ("Converted to client " ++ client.number)
                , navigateTo model.key ("/clients/" ++ String.fromInt client.id)
                ]
            )

        ConvertDone (Err e) ->
            ( model, toast "error" (httpError e) )

        NoteDraftChanged v ->
            ( { model | noteDraft = v }, Cmd.none )

        NoteSubmitted id ->
            if String.trim model.noteDraft == "" then
                ( model, Cmd.none )

            else
                ( model, Api.addNote ctx id model.noteDraft NoteDone )

        NoteDone (Ok _) ->
            ( { model | noteDraft = "" }
            , Cmd.batch [ toast "success" "Note added", reloadCurrent model ]
            )

        NoteDone (Err e) ->
            ( model, toast "error" (httpError e) )

        -- ----- filters / bulk -----
        SearchChanged v ->
            ( { model | q = v, pageOffset = 0 }, Task.perform (\_ -> SearchReady "leads" v) (Process.sleep 300) )

        StageFilterChanged v ->
            ( { model | fStage = v, pageOffset = 0, pageLoading = True }, Api.fetchFilteredLeads ctx { model | fStage = v } 0 (acceptLoad ({ model | fStage = v, pageOffset = 0 }) LeadsLoaded) )

        QualityFilterChanged v ->
            ( { model | fQuality = v, pageOffset = 0, pageLoading = True }, Api.fetchFilteredLeads ctx { model | fQuality = v } 0 (acceptLoad ({ model | fQuality = v, pageOffset = 0 }) LeadsLoaded) )

        SourceFilterChanged v ->
            ( { model | fSource = v, pageOffset = 0, pageLoading = True }, Api.fetchFilteredLeads ctx { model | fSource = v } 0 (acceptLoad ({ model | fSource = v, pageOffset = 0 }) LeadsLoaded) )

        SortByChanged v ->
            ( { model | sortBy = v, pageOffset = 0, pageLoading = True }, Api.fetchFilteredLeads ctx { model | sortBy = v } 0 (acceptLoad ({ model | sortBy = v, pageOffset = 0 }) LeadsLoaded) )

        SortDirToggled ->
            ( { model | sortAsc = not model.sortAsc, pageOffset = 0 }, Api.fetchFilteredLeads ctx { model | sortAsc = not model.sortAsc } 0 (acceptLoad ({ model | sortAsc = not model.sortAsc, pageOffset = 0 }) LeadsLoaded) )

        ClearFilters ->
            let next = { model | q = "", fStage = "All", fQuality = "All", fSource = "All", pageOffset = 0, pageLoading = True, selected = Set.empty } in
            ( next, Api.fetchFilteredLeads ctx next 0 (acceptLoad next LeadsLoaded) )

        RowChecked id flag ->
            ( { model
                | selected =
                    if flag then
                        Set.insert id model.selected

                    else
                        Set.remove id model.selected
              }
            , Cmd.none
            )

        SelectAllChecked flag ->
            ( { model
                | selected =
                    if flag then
                        Set.fromList (List.map .id (Views.filteredLeads model))

                    else
                        Set.empty
              }
            , Cmd.none
            )

        BulkAdvanceClicked ->
            ( model
            , Api.bulkLeads ctx
                { op = "advance", ids = Set.toList model.selected, consultantId = Nothing }
                BulkDone
            )

        BulkAssignPicked userIdStr ->
            case String.toInt userIdStr of
                Nothing ->
                    ( model, Cmd.none )

                Just uid ->
                    ( model
                    , Api.bulkLeads ctx
                        { op = "assign", ids = Set.toList model.selected, consultantId = Just uid }
                        BulkDone
                    )

        BulkDeleteClicked ->
            ( model
            , Api.bulkLeads ctx
                { op = "delete", ids = Set.toList model.selected, consultantId = Nothing }
                BulkDone
            )

        BulkDone (Ok _) ->
            ( { model | selected = Set.empty }
            , Cmd.batch [ toast "success" "Bulk action applied", reloadCurrent model ]
            )

        BulkDone (Err e) ->
            ( model, toast "error" (httpError e) )

        -- ----- tasks -----
        TaskStatusPicked id status ->
            let
                allTasks = model.tasks ++ (Maybe.map .tasks model.detail |> Maybe.withDefault []) ++ (Maybe.map .tasks model.clientDetail |> Maybe.withDefault [])
                revision = allTasks |> List.filter (\task -> task.id == id) |> List.head |> Maybe.map .revision |> Maybe.withDefault 0
            in
            ( model, Api.setTaskStatus ctx id revision status TaskStatusDone )

        TaskStatusDone (Ok _) ->
            ( model, Cmd.batch [ toast "success" "Task updated", reloadCurrent model ] )

        TaskStatusDone (Err e) ->
            ( model, toast "error" (httpError e) )

        TaskDeleted id ->
            ( model, Api.deleteTask ctx id TaskDeleteDone )

        TaskDeleteDone (Ok _) ->
            ( model, Cmd.batch [ toast "success" "Task deleted", reloadCurrent model ] )

        TaskDeleteDone (Err e) ->
            ( model, toast "error" (httpError e) )

        ToggleGlobalAddTask ->
            ( { model
                | showGlobalAddTask = not model.showGlobalAddTask
                , addTask = State.emptyAddTask
              }
            , Cmd.none
            )

        UpdateAddTask f ->
            ( { model | addTask = f model.addTask }, Cmd.none )

        SubmitAddTaskFor leadId ->
            submitTask model ctx leadId

        SubmitClientTask cid ->
            ( model, Api.createTask ctx (clientTaskBody model cid) AddTaskDone )

        SubmitAddTaskGlobal ->
            if String.startsWith "client:" model.addTask.leadId then
                let
                    cid = String.dropLeft 7 model.addTask.leadId |> String.toInt |> Maybe.withDefault 0
                in
                ( model, Api.createTask ctx (clientTaskBody model cid) AddTaskDone )
            else
                case String.toInt model.addTask.leadId of
                    Nothing -> ( model, toast "error" "Choose a lead or client first" )
                    Just leadId -> submitTask model ctx leadId

        AddTaskDone (Ok task) ->
            ( { model | showGlobalAddTask = False, addTask = State.emptyAddTask }
            , Cmd.batch
                [ toast "success" "Task created"
                , reloadCurrent model
                ]
            )

        AddTaskDone (Err e) ->
            ( model, toast "error" (httpError e) )

        -- ----- clients -----
        ClientSearchChanged v ->
            ( { model | clientQ = v, pageOffset = 0 }, Task.perform (\_ -> SearchReady "clients" v) (Process.sleep 300) )

        OpenAddClient ->
            ( { model
                | showClientForm = True
                , clientEditingId = Nothing
                , clientForm = State.emptyClientForm
              }
            , Cmd.none
            )

        OpenClientEditor _ ->
            case model.clientDetail of
                Nothing ->
                    ( model, Cmd.none )

                Just cd ->
                    ( { model
                        | showClientForm = True
                        , clientEditingId = Just cd.client.id
                        , clientForm = State.clientFormOf cd.client
                        , recordBaseline = clientPayload { model | clientForm = State.clientFormOf cd.client }
                      }
                    , Cmd.none
                    )

        CloseClientForm ->
            ( { model | showClientForm = False }, Cmd.none )

        UpdateClientForm f ->
            ( { model | clientForm = f model.clientForm }, Cmd.none )

        SubmitClientForm ->
            case model.clientEditingId of
                Just cid ->
                    ( model
                    , Api.updateClient ctx cid (clientPayload model) ClientUpdated
                    )

                Nothing ->
                    ( model
                    , Api.createClient ctx (clientPayload model) ClientFormSaved
                    )

        ClientUpdated (Ok _) ->
            ( { model | showClientForm = False }
            , Cmd.batch [ toast "success" "Client saved", reloadCurrent model ]
            )

        ClientUpdated (Err (Http.BadStatus 409)) ->
            beginConflict model "clients" (Maybe.withDefault 0 model.clientEditingId) model.recordBaseline (clientPayload model)

        ClientUpdated (Err e) ->
            ( model, toast "error" (httpError e) )

        ClientFormSaved (Ok _) ->
            ( { model | showClientForm = False }
            , Cmd.batch [ toast "success" "Client saved", reloadCurrent model ]
            )

        ClientFormSaved (Err e) ->
            ( model, toast "error" (httpError e) )

        DeleteClientConfirmed id ->
            ( model
            , Api.deleteClient ctx id DeleteClientDone
            )

        DeleteClientDone (Ok _) ->
            ( model
            , Cmd.batch [ toast "success" "Client deleted", navigateTo model.key "/clients" ]
            )

        DeleteClientDone (Err e) ->
            ( model, toast "error" (httpError e) )

        OpenCaseForm mcase ->
            ( { model
                | recordBaseline = Maybe.map (State.caseFormOf >> casePayload) mcase |> Maybe.withDefault E.null
                , caseForm =
                    Just
                        (Maybe.map State.caseFormOf mcase
                            |> Maybe.withDefault State.emptyCaseForm
                        )
              }
            , Cmd.none
            )

        CloseCaseForm ->
            ( { model | caseForm = Nothing }, Cmd.none )

        UpdateCaseForm f ->
            ( { model | caseForm = Maybe.map f model.caseForm }, Cmd.none )

        SubmitCaseForm clientId ->
            case model.caseForm of
                Nothing ->
                    ( model, Cmd.none )

                Just cf ->
                    ( model
                    , Api.upsertCase ctx clientId
                        (withRevision cf.revision (Types.encodeCaseInput
                            { category = cf.category
                            , destination = cf.destination
                            , stage = cf.stage
                            , deadline = cf.deadline
                            , caseId = cf.caseId
                            }
                        ))
                        CaseFormSaved
                    )

        CaseFormSaved (Ok cd) ->
            ( { model | caseForm = Nothing, clientDetail = Just cd }
            , Cmd.batch [toast "success" "Case saved",reloadCurrent model]
            )

        CaseFormSaved (Err (Http.BadStatus 409)) ->
            beginConflict model "cases" (Maybe.andThen .caseId model.caseForm |> Maybe.withDefault 0) model.recordBaseline (Maybe.map casePayload model.caseForm |> Maybe.withDefault E.null)

        CaseFormSaved (Err e) ->
            ( model, toast "error" (httpError e) )

        DeleteCaseClicked caseId ->
            ( model, Api.deleteCase ctx caseId DeleteCaseDone )

        DeleteCaseDone (Ok _) ->
            let next = { model | inlineOwner = ownerForUrl model.url, featureForm = Dict.insert "owner" (ownerForUrl model.url) (Features.defaults model.inlineSection) } in
            ( next, Cmd.batch [ toast "success" "Case deleted", reloadCurrent next ] )

        DeleteCaseDone (Err e) ->
            ( model, toast "error" (httpError e) )

        -- ----- documents -----
        DocPicked file ->
            ( { model | pendingDoc = Just file }, Cmd.none )

        DocCleared ->
            ( { model | pendingDoc = Nothing }, Cmd.none )

        UploadLeadDocClicked id ->
            case model.pendingDoc of
                Nothing ->
                    ( model, toast "error" "Choose a file first" )

                Just file ->
                    ( model, Api.uploadLeadDocument ctx id file LeadDocUploaded )

        UploadClientDocClicked id ->
            case model.pendingDoc of
                Nothing ->
                    ( model, toast "error" "Choose a file first" )

                Just file ->
                    ( model, Api.uploadClientDocument ctx id file ClientDocUploaded )

        LeadDocUploaded (Ok detail) ->
            ( { model | detail = Just detail, pendingDoc = Nothing }
            , toast "success" "Document uploaded"
            )

        LeadDocUploaded (Err e) ->
            ( model, toast "error" (httpError e) )

        ClientDocUploaded (Ok cd) ->
            ( { model | clientDetail = Just cd, pendingDoc = Nothing }
            , Cmd.batch [toast "success" "Document uploaded for malware scanning",reloadCurrent model]
            )

        ClientDocUploaded (Err e) ->
            ( model, toast "error" (httpError e) )

        DocDeleted id ->
            ( model, Api.deleteDocument ctx id DocDeleteDone )

        DocDeleteDone (Ok _) ->
            ( model
            , Cmd.batch [ toast "success" "Document deleted", reloadCurrent model ]
            )

        DocDeleteDone (Err e) ->
            ( model, toast "error" (httpError e) )

        -- ----- csv import -----
        ImportFilePicked file ->
            ( { model | pendingImport = Just file }, Cmd.none )

        LeadImportClicked ->
            case model.pendingImport of
                Nothing ->
                    ( model, toast "error" "Choose a CSV file first" )

                Just file ->
                    ( model, Api.importLeads ctx file LeadsImported )

        LeadsImported (Ok res) ->
            let
                failCount =
                    List.length res.failed

                failureSummary =
                    res.failed
                        |> List.take 3
                        |> List.map (\fe -> "row " ++ String.fromInt fe.row ++ ": " ++ fe.error)
                        |> String.join "; "

                failToast =
                    if failCount == 0 then
                        Cmd.none

                    else
                        toast "error"
                            ("Rows failed ("
                                ++ String.fromInt failCount
                                ++ ") — "
                                ++ failureSummary
                            )
            in
            ( { model | pendingImport = Nothing }
            , Cmd.batch
                [ toast "success"
                    ("Imported "
                        ++ String.fromInt res.imported
                        ++ " lead"
                        ++ (if res.imported == 1 then
                                ""

                            else
                                "s"
                           )
                    )
                , failToast
                , reloadCurrent model
                ]
            )

        LeadsImported (Err e) ->
            ( model, toast "error" (httpError e) )

        -- ----- users / account -----
        OpenAddUser ->
            ( { model | showUserForm = True, userForm = State.emptyUserForm }
            , Cmd.none
            )

        OpenUserEditor uid ->
            case List.filter (\u -> u.id == uid) model.users of
                (u :: _) ->
                    ( { model | showUserForm = True, userForm = State.userFormOf u, recordBaseline = E.object [("uuName",E.string u.name),("uuRole",E.string u.role)] }
                    , Cmd.none
                    )

                [] ->
                    ( model, Cmd.none )

        CloseUserForm ->
            ( { model | showUserForm = False }, Cmd.none )

        UpdateUserForm f ->
            ( { model | userForm = f model.userForm }, Cmd.none )

        SubmitUserForm ->
            let
                f =
                    model.userForm
            in
            case f.userId of
                Nothing ->
                    if f.password /= "" && String.length f.password < 12 then
                        ( model, toast "error" "Password must be at least 12 characters" )

                    else
                        ( model
                        , Api.createUser ctx
                            (Types.encodeNewUser
                                { name = f.name
                                , email = f.email
                                , role = f.role
                                , password = f.password
                                }
                            )
                            UserSaved
                        )

                Just uid ->
                    ( model
                    , Api.updateUser ctx uid
                        (withRevision f.revision (Types.encodeUpdateUser
                            { name = f.name
                            , role = f.role
                            , password = f.password
                            }
                        ))
                        UserUpdatedDone
                    )

        UserSaved (Ok u) ->
            ( { model | showUserForm = False, users = model.users ++ [ u ] }
            , Cmd.batch [ toast "success" ("User " ++ u.name ++ " created"), reloadCurrent model ]
            )

        UserSaved (Err e) ->
            ( model, toast "error" (httpError e) )

        UserUpdatedDone (Ok _) ->
            ( { model | showUserForm = False }
            , Cmd.batch [ toast "success" "User saved", reloadCurrent model ]
            )

        UserUpdatedDone (Err (Http.BadStatus 409)) ->
            beginConflict model "users" (Maybe.withDefault 0 model.userForm.userId) model.recordBaseline (E.object [("uuName",E.string model.userForm.name),("uuRole",E.string model.userForm.role)])

        UserUpdatedDone (Err e) ->
            ( model, toast "error" (httpError e) )

        DeleteUserConfirmed uid ->
            ( model, Api.deleteUser ctx uid DeleteUserDone )

        DeleteUserDone (Ok _) ->
            ( model
            , Cmd.batch [ toast "success" "User deleted", reloadCurrent model ]
            )

        DeleteUserDone (Err e) ->
            ( model, toast "error" (httpError e) )

        TogglePwModal ->
            ( { model
                | showPwModal = not model.showPwModal
                , pwCurrent = ""
                , pwNew = ""
                , pwConfirm = ""
              }
            , Cmd.none
            )

        PwCurrentChanged v ->
            ( { model | pwCurrent = v }, Cmd.none )

        PwNewChanged v ->
            ( { model | pwNew = v }, Cmd.none )

        PwConfirmChanged v ->
            ( { model | pwConfirm = v }, Cmd.none )

        SubmitPasswordChange ->
            let
                validationError =
                    if String.length model.pwNew < 12 then
                        "New password must be at least 12 characters"

                    else if model.pwNew /= model.pwConfirm then
                        "Passwords do not match"

                    else
                        ""
            in
            if validationError /= "" then
                ( model, toast "error" validationError )

            else
                ( model
                , Api.changePassword ctx model.pwCurrent model.pwNew PasswordChangeDone
                )

        PasswordChangeDone (Ok _) ->
            ( { model
                | showPwModal = False
                , loginNotice = "Your password was updated. Sign in with your new password."
                , pwCurrent = ""
                , pwNew = ""
                , pwConfirm = ""
              }
            , Cmd.batch [ Api.logout ctx LogoutDone, toast "success" "Password updated. Sign in again." ]
            )

        PasswordChangeDone (Err e) ->
            ( model, toast "error" (httpError e) )

        -- ----- chrome -----
        NotifBellClicked ->
            ( { model | notifOpen = not model.notifOpen }, Cmd.none )

        NavigateTo path ->
            ( { model | notifOpen = False, pageError = "" }, if path == model.url.path then reloadCurrent model else Nav.pushUrl model.key path )

        ToastPushed kind textMsg ->
            pushToast model kind textMsg

        ToastExpired id ->
            ( { model | toasts = List.filter (\t -> t.id /= id) model.toasts }
            , Cmd.none
            )



-- ---------- small helpers used by update ----------


submitTask : Model -> Api.Ctx -> Int -> ( Model, Cmd Msg )
submitTask model ctx leadId =
    if String.trim model.addTask.title == "" then
        ( model, Cmd.none )

    else
        ( model
        , Api.createTask ctx
            (Types.encodeNewTask
                { leadId = leadId
                , title = model.addTask.title
                , description = model.addTask.description
                , dueDate = model.addTask.dueDate
                , priority = model.addTask.priority
                }
            )
            AddTaskDone
        )


reloadCurrent : Model -> Cmd Msg
reloadCurrent model =
    routeCmd model (State.routeOf model.url)


clientPayload : Model -> E.Value
clientPayload model =
    withRevision model.clientForm.revision (Types.encodeNewClient
        { fullName = model.clientForm.fullName
        , email = model.clientForm.email
        , phone = model.clientForm.phone
        , officerId = String.toInt model.clientForm.officerId
        })


justOf : Result Http.Error a -> Maybe a
justOf r =
    Result.toMaybe r


toast : String -> String -> Cmd Msg
toast kind textMsg =
    Task.perform identity
        (Task.succeed (ToastPushed kind textMsg))


pushToast : Model -> String -> String -> ( Model, Cmd Msg )
pushToast model kind textMsg =
    let
        id =
            model.toastSeq + 1

        newToast =
            { id = id, kind = kind, msg = textMsg }
    in
    ( { model | toasts = model.toasts ++ [ newToast ], toastSeq = id }
    , Task.perform (always (ToastExpired id))
        (Process.sleep 3500)
    )


httpError : Http.Error -> String
httpError err =
    case err of
        Http.BadUrl url ->
            "Bad URL: " ++ url

        Http.Timeout ->
            "Request timed out"

        Http.NetworkError ->
            "Network error — is the API running?"

        Http.BadStatus code ->
            case code of
                401 ->
                    "Not authenticated — sign in again"

                403 ->
                    "You don't have permission for that"

                404 ->
                    "Not found"

                409 ->
                    "This record or action changed. Refresh and review the latest version before trying again."

                428 ->
                    "Reload this record to obtain its current version before saving."

                429 ->
                    "Too many requests. Wait before trying again."

                423 ->
                    "File quarantined: wait for a successful malware scan. Infected files and failed scans stay blocked."

                _ ->
                    "Server error (" ++ String.fromInt code ++ ")"

        Http.BadBody body ->
            String.left 240 body



-- ---------- view ----------


view : Model -> Browser.Document Msg
view model =
    { title = "ECC · Client workspace"
    , body =
        [ div
            [ class
                (if model.darkMode then
                    "app-root dark-mode"

                 else
                    "app-root"
                )
            ]
            (bodyView model)
        ]
    }


bodyView : Model -> List (Html Msg)
bodyView model =
    if model.url.path == "/portal" then
        [ Features.portalView model ]

    else if not model.authChecked then
        [ div [ class "login-wrap" ] [ Ui.spinner ] ]

    else if model.user == Nothing then
        [ Views.loginView model ]

    else
        List.concat
            [ [ a [ href "#main-content", class "skip-link" ] [ text "Skip to content" ], headerBar model
              , Html.main_ [ class "container", Html.Attributes.id "main-content", Html.Attributes.tabindex -1 ] [ workspaceHeading model, if model.pageError /= "" then div [ class "error-banner", Html.Attributes.attribute "role" "alert" ] [ text model.pageError, button [ class "btn btn-sm btn-outline", onClick (NavigateTo model.url.path) ] [ text "Try again" ] ] else span [] [], if model.pageError /= "" && (model.detail == Nothing && model.clientDetail == Nothing) then span [] [] else pageView model, pagination model ]
              ]
            , if model.showUserForm then
                [ Views.userFormModal model ]

              else
                []
            , if model.showPwModal then
                [ Views.passwordModal model ]

              else
                []
            , [ Features.conflictView model ]
            , case model.confirmation of
                Just (message,_) -> [ Ui.modal "Confirm this action" (div [] [ Html.p [] [ text message ], div [ class "flex", Html.Attributes.style "margin-top" "20px" ] [ button [ class "btn btn-outline", onClick ConfirmDismissed ] [ text "Cancel" ], button [ class "btn btn-primary", onClick ConfirmAccepted ] [ text "Confirm" ] ] ]) ]
                Nothing -> []
            , [ Views.toastStack model ]
            ]


pageView : Model -> Html Msg
pageView model =
    case State.routeOf model.url of
        Dashboard ->
            Views.dashboardView model

        LeadsPage ->
            Views.leadsView model

        LeadDetailPage id ->
            Views.leadDetailView model id

        ClientsPage ->
            Views.clientsView model

        ClientDetailPage id ->
            Views.clientDetailView model id

        TasksPage ->
            Views.tasksView model

        UsersPage ->
            Views.usersView model

        AuditPage ->
            Views.auditView model

        WorkspacePage kind ->
            if String.startsWith "work/" kind then Features.view model (String.dropLeft 5 kind) else Operations.view model kind


headerBar : Model -> Html Msg
headerBar model =
    let
        current =
            model.url.path

        navBtn path label =
            a
                [ class
                    (if isActive path then
                        "nav-link active"

                     else
                        "nav-link"
                    )
                , href path
                , Html.Attributes.attribute "aria-current" (if isActive path then "page" else "false")
                ]
                [ Ui.icon (if path == "/" then "dashboard" else if path == "/users" then "clients" else String.dropLeft 1 path), span [] [ text label ] ]

        isActive path =
            if path == "/" then
                current == "/"

            else
                String.startsWith path current

        user_ =
            Maybe.withDefault { id = 0, email = "", name = "", role = "", revision = 1, mfaRequired = False } model.user
    in
    div [ class "header" ]
        [ div [ class "logo" ]
            [ div [ class "logo-icon" ] [ text "E" ]
            , strong [] [ text "ECC CRM" ]
            ]
        , Html.nav [ class "nav", Html.Attributes.attribute "aria-label" "Main navigation" ]
            [ div [ class "nav-group" ]
                [ div [ class "nav-section-label" ] [ text "WORKSPACE" ]
                , navBtn "/" "Dashboard"
                , navBtn "/leads" "Leads"
                , navBtn "/clients" "Clients"
                , navBtn "/tasks" "Tasks"
                ]
            , div [ class "nav-group" ]
                [ div [ class "nav-section-label" ] [ text "KEEP ON TRACK" ]
                , navBtn "/reminders" "Reminders"
                , navBtn "/duplicates" "Duplicates"
                ]
            , if user_.role == "admin" then
                div [ class "nav-group" ]
                    [ div [ class "nav-section-label" ] [ text "MANAGE" ]
                    , navBtn "/users" "Team"
                    , navBtn "/archive" "Archive"
                    , navBtn "/system" "System"
                    , navBtn "/audit" "Audit"
                    ]
              else
                span [] []
            ]
        , Html.details [ class "workspace-tools" ]
            [ Html.summary [] [ text "Workspace tools" ]
            , div [class "tools-menu"] (List.map (\(section,labelText) -> a [href ("/work/" ++ section),class "nav-link"] [text labelText])
                ([ ("tasks","Edit and assign tasks"),("history","Client/case history"),("documents","Document checklists"),("reminders","Email reminders"),("search","Search and saved views"),("appointments","Appointments"),("communication","Email a contact"),("portal","Client portal"),("security","Account security"),("notifications","Notification centre"),("mail","Email delivery") ]
                ++ (if user_.role=="admin" then [("merge","Merge duplicates"),("reports","Reports"),("invoices","Invoices"),("ageing","Case ageing"),("bottlenecks","Case bottlenecks"),("trends","Workload trends")] else [])))
            ]
        , div [ class "header-right" ]
            [ button
                [ class "btn btn-sm btn-outline"
                , onClick TogglePwModal
                ]
                [ text "Password" ]
            , button [ class "btn btn-sm btn-outline dark-toggle", onClick ToggleDarkMode ]
                [ text
                    (if model.darkMode then
                        "☀ Light"

                     else
                        "☾ Dark"
                    )
                ]
            , span [ class "user-chip" ]
                [ Ui.avatar user_.name
                , span [ class "user-identity" ] [ strong [] [ text user_.name ], span [ class "user-role" ] [ text user_.role ] ]
                ]
            , button [ class "btn-logout", onClick LogoutClicked ] [ text "Log out" ]
            ]
        ]



-- ---------- subscriptions ----------


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ loadToken GotStoredToken
        , loadDark GotStoredDark
        ]



-- ports for JS glue (defined above; repeated imports kept minimal)


navigateTo : Nav.Key -> String -> Cmd msg
navigateTo key path =
    Nav.pushUrl key path


resultError : Result Http.Error a -> String
resultError result = case result of
    Ok _ -> ""
    Err err -> httpError err

workspaceHeading : Model -> Html Msg
workspaceHeading model =
    let
        (title,subtitle) = case State.routeOf model.url of
            Dashboard -> ("A clear view of what’s next.","Your relationships, progress and priorities in one place.")
            LeadsPage -> ("Build your next relationship.","Keep every conversation moving toward a clear next step.")
            ClientsPage -> ("Great service starts here.","A shared view of every client and their journey.")
            TasksPage -> ("Make room for your best work.","Turn follow-ups and deadlines into progress.")
            UsersPage -> ("Your people, connected.","Invite colleagues and manage their access.")
            AuditPage -> ("Every change, accounted for.","A complete history of activity across your workspace.")
            _ -> ("Your client workspace.","Keep the details close and the next step clear.")
        section = case State.routeOf model.url of
            Dashboard -> "Overview"
            LeadsPage -> "Leads"
            LeadDetailPage _ -> "Lead details"
            ClientsPage -> "Clients"
            ClientDetailPage _ -> "Client details"
            TasksPage -> "Tasks"
            UsersPage -> "Team"
            AuditPage -> "Audit history"
            WorkspacePage kind -> if kind == "metrics" then "System" else String.toUpper (String.left 1 kind) ++ String.dropLeft 1 kind
    in
    div [ class "workspace-heading" ]
        [ div [ class "workspace-topline" ]
            [ div [ class "breadcrumb" ] [ a [ href "/" ] [ text "Workspace" ], span [] [ text "/" ], span [] [ text section ] ]
            , div [ class "workspace-date" ] [ Ui.icon "clock", text model.today ]
            ]
        , div [ class "heading-content" ]
            [ div [] [ div [ class "eyebrow" ] [ text "ECC / CLIENT OPERATIONS" ], Html.h1 [] [ text title ], Html.p [] [ text subtitle ] ]
            , if State.routeOf model.url == Dashboard then a [ class "btn btn-primary heading-action", href "/leads" ] [ text "View pipeline", Ui.icon "arrow" ] else span [] []
            ]
        ]

pagination : Model -> Html Msg
pagination model =
    let
        size = case State.routeOf model.url of
            LeadsPage -> Just (List.length model.leads)
            ClientsPage -> Just (List.length model.clients)
            TasksPage -> Just (List.length model.tasks)
            WorkspacePage kind -> if kind == "metrics" then Nothing else Just (List.length model.opsData)
            _ -> Nothing
    in
    case size of
        Nothing -> span [] []
        Just count -> div [ class "pagination", Html.Attributes.attribute "aria-label" "Pagination" ]
            [ span [] [ text (if model.pageLoading then "Loading records…" else String.fromInt count ++ " records · page " ++ String.fromInt (1 + model.pageOffset // 50)) ]
            , button [ class "btn btn-outline", Html.Attributes.disabled (model.pageOffset == 0 || model.pageLoading), onClick (PageStep -1) ] [ text "← Previous" ]
            , button [ class "btn btn-outline", Html.Attributes.disabled (count < 50 || model.pageLoading), onClick (PageStep 1) ] [ text "Next →" ]
            ]


expiredSession : Msg -> Bool
expiredSession msg =
    case msg of
        ConflictLoaded (Err (Http.BadStatus 401)) -> True
        FeatureDone (Err (Http.BadStatus 401)) -> True
        FeatureLoaded (Err (Http.BadStatus 401)) -> True
        LeadsLoaded (Err (Http.BadStatus 401)) -> True
        ClientsLoaded (Err (Http.BadStatus 401)) -> True
        TasksLoaded (Err (Http.BadStatus 401)) -> True
        DetailLoaded (Err (Http.BadStatus 401)) -> True
        ClientDetailLoaded (Err (Http.BadStatus 401)) -> True
        StatsLoaded (Err (Http.BadStatus 401)) -> True
        OperationsLoaded (Err (Http.BadStatus 401)) -> True
        OperationDone (Err (Http.BadStatus 401)) -> True
        UsersLoaded (Err (Http.BadStatus 401)) -> True
        AuditLoaded (Err (Http.BadStatus 401)) -> True
        _ -> False


clientTaskBody : Model -> Int -> E.Value
clientTaskBody model cid =
    let form = model.addTask in
    E.object
        [ ("ntLeadId", E.null)
        , ("ntClientId", E.int cid)
        , ("ntTitle", E.string form.title)
        , ("ntDescription", E.string form.description)
        , ("ntDueDate", if form.dueDate == "" then E.null else E.string form.dueDate)
        , ("ntPriority", E.string form.priority)
        ]

featureSection : Model -> String
featureSection model =
    case State.routeOf model.url of
        ClientDetailPage _ -> model.inlineSection
        _ -> String.dropLeft 6 model.url.path

withRevision : Int -> E.Value -> E.Value
withRevision revision value =
    E.object (("expectedRevision",E.int revision) :: (D.decodeValue (D.keyValuePairs D.value) value |> Result.withDefault []))

ownerForUrl : Url -> String
ownerForUrl url = case State.routeOf url of
    ClientDetailPage cid -> "client:" ++ String.fromInt cid
    _ -> ""

inlinePath : Model -> Int -> String
inlinePath model cid =
    "record/" ++ (if String.startsWith "case:" model.inlineOwner then String.replace ":" "/" model.inlineOwner else "client/" ++ String.fromInt cid) ++ "/" ++ model.inlineSection

dictValue : Dict.Dict String String -> E.Value
dictValue fields = E.object (Dict.toList fields |> List.map (Tuple.mapSecond E.string))

beginConflict : Model -> String -> Int -> E.Value -> E.Value -> (Model,Cmd Msg)
beginConflict model kind rid original edited =
    ( { model | conflictKind = kind, conflictCurrent = E.null, conflictOriginal = Features.formValues original, conflictEdits = Features.formValues edited }
    , Api.featureGet {base=model.apiBase,token=model.token} ("conflict/" ++ kind ++ "/" ++ String.fromInt rid) "" 0 (acceptLoad model ConflictLoaded) )

casePayload : State.CaseForm -> E.Value
casePayload cf = Types.encodeCaseInput { category=cf.category,destination=cf.destination,stage=cf.stage,deadline=cf.deadline,caseId=cf.caseId }
