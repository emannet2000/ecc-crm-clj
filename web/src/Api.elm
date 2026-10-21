module Api exposing
    ( checklistUpload, featureGet, featurePost, portalGet, portalPost, portalUpload
    , fetchFilteredLeads
    , fetchOperations
    , operation
    , recover
    , resetPassword
    , logout
    , fetchLeadsPage
    , fetchClientsPage
    , fetchTasksPage
    , Ctx
    , computeBase
    , login
    , me
    , fetchUsers
    , fetchLeads
    , fetchLeadDetail
    , createLead
    , updateLead
    , deleteLead
    , advanceLead
    , convertLead
    , addNote
    , bulkLeads
    , fetchTasks
    , createTask
    , setTaskStatus
    , deleteTask
    , fetchActivities
    , fetchClients
    , fetchClientDetail
    , createClient
    , updateClient
    , deleteClient
    , upsertCase
    , deleteCase
    , uploadLeadDocument
    , uploadClientDocument
    , deleteDocument
    , documentDownloadUrl
    , exportCsvUrl
    , importLeads
    , createUser
    , updateUser
    , deleteUser
    , changePassword
    , fetchAudit
    , fetchStats
    )

{-| Thin wrappers over elm/http for every API endpoint.  All requests carry
the JWT bearer token when one is available.
-}

import File exposing (File)
import Http
import Json.Decode as D
import Json.Encode as E
import Url

import Types exposing (..)


{-| The API serves this SPA on the same origin in every environment. -}
computeBase : { protocol : String, host : String, port_ : Maybe Int } -> String
computeBase _ =
    ""


type alias Ctx =
    { base : String, token : Maybe String }


authedRequest :
    Ctx
    -> String
    -> String
    -> Maybe Http.Body
    -> D.Decoder a
    -> (Result Http.Error a -> msg)
    -> Cmd msg
authedRequest ctx method path body decoder toMsg =
    Http.request
        { method = method
        , headers =
            []
        , url = ctx.base ++ path
        , body = Maybe.withDefault Http.emptyBody body
        , expect = expectJson toMsg decoder
        , timeout = Just 30000
        , tracker = Nothing
        }



-- ---------- auth ----------


type alias LoginResult =
    Result Http.Error LoginResponse


login : Ctx -> String -> String -> String -> (LoginResult -> msg) -> Cmd msg
login ctx email password otp toMsg =
    Http.post
        { url = ctx.base ++ "/api/auth/login"
        , body = Http.jsonBody (E.object [("lrEmail",E.string email),("lrPassword",E.string password),("lrOtp",E.string otp)])
        , expect = expectJson toMsg loginResponseDecoder
        }


me : Ctx -> (Result Http.Error User -> msg) -> Cmd msg
me ctx toMsg =
    authedRequest ctx "GET" "/api/auth/me" Nothing userDecoder toMsg



-- ---------- users / leads / tasks / clients / stats ----------


fetchUsers : Ctx -> (Result Http.Error (List User) -> msg) -> Cmd msg
fetchUsers ctx =
    authedRequest ctx "GET" "/api/users" Nothing (D.list userDecoder)


fetchLeads : Ctx -> (Result Http.Error (List Lead) -> msg) -> Cmd msg
fetchLeads ctx =
    authedRequest ctx "GET" "/api/leads" Nothing (D.list leadDecoder)


fetchLeadDetail : Ctx -> Int -> (Result Http.Error LeadDetail -> msg) -> Cmd msg
fetchLeadDetail ctx id =
    authedRequest ctx "GET" ("/api/leads/" ++ String.fromInt id) Nothing leadDetailDecoder


createLead : Ctx -> E.Value -> (Result Http.Error Lead -> msg) -> Cmd msg
createLead ctx body =
    authedRequest ctx "POST" "/api/leads" (Just <| Http.jsonBody body) leadDecoder


updateLead : Ctx -> Int -> E.Value -> (Result Http.Error Lead -> msg) -> Cmd msg
updateLead ctx id body =
    authedRequest ctx "PATCH" ("/api/leads/" ++ String.fromInt id) (Just <| Http.jsonBody body) leadDecoder


deleteLead : Ctx -> Int -> (Result Http.Error () -> msg) -> Cmd msg
deleteLead ctx id =
    authedRequest ctx "DELETE" ("/api/leads/" ++ String.fromInt id) Nothing ignoreDecoder


advanceLead : Ctx -> Int -> (Result Http.Error Lead -> msg) -> Cmd msg
advanceLead ctx id =
    authedRequest ctx "POST" ("/api/leads/" ++ String.fromInt id ++ "/advance") Nothing leadDecoder


convertLead : Ctx -> Int -> (Result Http.Error Client -> msg) -> Cmd msg
convertLead ctx id =
    authedRequest ctx "POST" ("/api/leads/" ++ String.fromInt id ++ "/convert") Nothing clientDecoder


addNote : Ctx -> Int -> String -> (Result Http.Error () -> msg) -> Cmd msg
addNote ctx id note =
    authedRequest ctx
        "POST"
        ("/api/leads/" ++ String.fromInt id ++ "/notes")
        (Just <| Http.jsonBody (encodeNote note))
        ignoreDecoder


bulkLeads : Ctx -> BulkSpec -> (Result Http.Error () -> msg) -> Cmd msg
bulkLeads ctx spec =
    authedRequest ctx "POST" "/api/bulk/leads" (Just <| Http.jsonBody (encodeBulkRequest spec)) ignoreDecoder


fetchTasks : Ctx -> (Result Http.Error (List Task) -> msg) -> Cmd msg
fetchTasks ctx =
    authedRequest ctx "GET" "/api/tasks" Nothing (D.list taskDecoder)


createTask : Ctx -> E.Value -> (Result Http.Error Task -> msg) -> Cmd msg
createTask ctx body =
    authedRequest ctx "POST" "/api/tasks" (Just <| Http.jsonBody body) taskDecoder


setTaskStatus : Ctx -> Int -> Int -> String -> (Result Http.Error () -> msg) -> Cmd msg
setTaskStatus ctx id revision status =
    authedRequest ctx
        "PATCH"
        ("/api/tasks/" ++ String.fromInt id)
        (Just <| Http.jsonBody (E.object [("tsrStatus", E.string status),("expectedRevision",E.int revision)]))
        ignoreDecoder


deleteTask : Ctx -> Int -> (Result Http.Error () -> msg) -> Cmd msg
deleteTask ctx id =
    authedRequest ctx "DELETE" ("/api/tasks/" ++ String.fromInt id) Nothing ignoreDecoder


fetchActivities : Ctx -> Int -> (Result Http.Error (List Activity) -> msg) -> Cmd msg
fetchActivities ctx limit =
    authedRequest ctx "GET" ("/api/activities?limit=" ++ String.fromInt limit) Nothing (D.list activityDecoder)


fetchClients : Ctx -> (Result Http.Error (List Client) -> msg) -> Cmd msg
fetchClients ctx =
    authedRequest ctx "GET" "/api/clients" Nothing (D.list clientDecoder)


fetchClientDetail : Ctx -> Int -> (Result Http.Error ClientDetail -> msg) -> Cmd msg
fetchClientDetail ctx id =
    authedRequest ctx "GET" ("/api/clients/" ++ String.fromInt id) Nothing clientDetailDecoder


createClient : Ctx -> E.Value -> (Result Http.Error Client -> msg) -> Cmd msg
createClient ctx body =
    authedRequest ctx "POST" "/api/clients" (Just <| Http.jsonBody body) clientDecoder


updateClient : Ctx -> Int -> E.Value -> (Result Http.Error () -> msg) -> Cmd msg
updateClient ctx id body =
    authedRequest ctx "PATCH" ("/api/clients/" ++ String.fromInt id) (Just <| Http.jsonBody body) ignoreDecoder


deleteClient : Ctx -> Int -> (Result Http.Error () -> msg) -> Cmd msg
deleteClient ctx id =
    authedRequest ctx "DELETE" ("/api/clients/" ++ String.fromInt id) Nothing ignoreDecoder


upsertCase : Ctx -> Int -> E.Value -> (Result Http.Error ClientDetail -> msg) -> Cmd msg
upsertCase ctx clientId body =
    authedRequest ctx "POST" ("/api/clients/" ++ String.fromInt clientId ++ "/cases") (Just <| Http.jsonBody body) clientDetailDecoder


deleteCase : Ctx -> Int -> (Result Http.Error () -> msg) -> Cmd msg
deleteCase ctx id =
    authedRequest ctx "DELETE" ("/api/cases/" ++ String.fromInt id) Nothing ignoreDecoder



-- ---------- documents ----------


{-| Multipart upload of one file attached to a lead; responds with the
refreshed lead detail (including the new documents list).
-}
uploadLeadDocument : Ctx -> Int -> File -> (Result Http.Error LeadDetail -> msg) -> Cmd msg
uploadLeadDocument ctx id file =
    uploadDocument ctx
        ("/api/leads/" ++ String.fromInt id ++ "/documents")
        file
        leadDetailDecoder


{-| Same as 'uploadLeadDocument' but attached to a client.
-}
uploadClientDocument : Ctx -> Int -> File -> (Result Http.Error ClientDetail -> msg) -> Cmd msg
uploadClientDocument ctx id file =
    uploadDocument ctx
        ("/api/clients/" ++ String.fromInt id ++ "/documents")
        file
        clientDetailDecoder


uploadDocument : Ctx -> String -> File -> D.Decoder a -> (Result Http.Error a -> msg) -> Cmd msg
uploadDocument ctx path file decoder toMsg =
    Http.request
        { method = "POST"
        , headers =
            []
        , url = ctx.base ++ path
        , body = Http.multipartBody [ Http.filePart "file" file ]
        , expect = expectJson toMsg decoder
        , timeout = Just 30000
        , tracker = Nothing
        }


deleteDocument : Ctx -> Int -> (Result Http.Error () -> msg) -> Cmd msg
deleteDocument ctx id =
    authedRequest ctx "DELETE" ("/api/documents/" ++ String.fromInt id) Nothing ignoreDecoder


{-| Direct download link for an @<a>@ — the API also accepts the token
as a query parameter because anchors cannot set headers.
-}
documentDownloadUrl : Ctx -> Int -> String
documentDownloadUrl ctx id =
    ctx.base ++ "/api/documents/" ++ String.fromInt id ++ "/download"


{-| Direct download link for a CSV export (leads\/clients) — same
query-token mechanism as document downloads.
-}
exportCsvUrl : Ctx -> String -> String
exportCsvUrl ctx kind =
    ctx.base ++ "/api/export/" ++ kind ++ ".csv"


{-| Upload a CSV file for bulk lead import.  The server parses the file and
answers with per-row success\/failure counts.
-}
importLeads : Ctx -> File -> (Result Http.Error ImportResult -> msg) -> Cmd msg
importLeads ctx file toMsg =
    Http.request
        { method = "POST"
        , headers =
            []
        , url = ctx.base ++ "/api/import/leads"
        , body = Http.multipartBody [ Http.filePart "file" file ]
        , expect = expectJson toMsg importResultDecoder
        , timeout = Just 30000
        , tracker = Nothing
        }



-- ---------- users / account ----------


createUser : Ctx -> E.Value -> (Result Http.Error User -> msg) -> Cmd msg
createUser ctx body =
    authedRequest ctx "POST" "/api/users" (Just <| Http.jsonBody body) userDecoder


updateUser : Ctx -> Int -> E.Value -> (Result Http.Error () -> msg) -> Cmd msg
updateUser ctx id body =
    authedRequest ctx "PATCH" ("/api/users/" ++ String.fromInt id) (Just <| Http.jsonBody body) ignoreDecoder


deleteUser : Ctx -> Int -> (Result Http.Error () -> msg) -> Cmd msg
deleteUser ctx id =
    authedRequest ctx "DELETE" ("/api/users/" ++ String.fromInt id) Nothing ignoreDecoder


{-| Change the signed-in user's own password.
-}
changePassword : Ctx -> String -> String -> (Result Http.Error () -> msg) -> Cmd msg
changePassword ctx current new =
    authedRequest ctx "PUT" "/api/auth/password"
        (Just <| Http.jsonBody (encodePasswordChange { current = current, new = new }))
        ignoreDecoder


fetchStats : Ctx -> (Result Http.Error Stats -> msg) -> Cmd msg
fetchStats ctx =
    authedRequest ctx "GET" "/api/stats" Nothing statsDecoder


{-| Latest audit-trail entries (admin-only endpoint).
-}
fetchAudit : Ctx -> Int -> (Result Http.Error (List AuditEntry) -> msg) -> Cmd msg
fetchAudit ctx limit =
    authedRequest ctx "GET" ("/api/audit?limit=" ++ String.fromInt limit)
        Nothing
        (D.list auditDecoder)



-- ---------- helpers ----------


ignoreDecoder : D.Decoder ()
ignoreDecoder =
    D.oneOf
        [ D.map (\_ -> ()) (D.dict D.value)
        , D.succeed ()
        ]


loginBody : String -> String -> E.Value
loginBody email password =
    E.object
        [ ( "lrEmail", E.string email )
        , ( "lrPassword", E.string password )
        ]

expectJson : (Result Http.Error a -> msg) -> D.Decoder a -> Http.Expect msg
expectJson toMsg decoder =
    Http.expectStringResponse toMsg (\response ->
        case response of
            Http.BadUrl_ url -> Err (Http.BadUrl url)
            Http.Timeout_ -> Err Http.Timeout
            Http.NetworkError_ -> Err Http.NetworkError
            Http.BadStatus_ metadata body ->
                if metadata.statusCode == 401 then
                    Err (Http.BadStatus 401)
                else
                    Err (Http.BadBody (D.decodeString (D.field "error" D.string) body |> Result.withDefault ("Request failed (" ++ String.fromInt metadata.statusCode ++ ")")))
            Http.GoodStatus_ _ body -> D.decodeString decoder body |> Result.mapError (D.errorToString >> Http.BadBody)
        )

logout : Ctx -> (Result Http.Error () -> msg) -> Cmd msg
logout ctx = authedRequest ctx "POST" "/api/auth/logout" Nothing ignoreDecoder

recover : Ctx -> String -> (Result Http.Error () -> msg) -> Cmd msg
recover ctx email = authedRequest ctx "POST" "/api/auth/recover" (Just (Http.jsonBody (E.object [("email",E.string email)]))) ignoreDecoder

resetPassword : Ctx -> String -> String -> (Result Http.Error () -> msg) -> Cmd msg
resetPassword ctx token password = authedRequest ctx "POST" "/api/auth/reset" (Just (Http.jsonBody (E.object [("token",E.string token),("password",E.string password)]))) ignoreDecoder

fetchOperations : Ctx -> String -> Int -> (Result Http.Error (List D.Value) -> msg) -> Cmd msg
fetchOperations ctx kind offset = authedRequest ctx "GET" ("/api/" ++ kind ++ "?limit=50&offset=" ++ String.fromInt offset) Nothing (D.list D.value)

operation : Ctx -> String -> (Result Http.Error () -> msg) -> Cmd msg
operation ctx path = authedRequest ctx "POST" ("/api/" ++ path) Nothing ignoreDecoder

fetchLeadsPage : Ctx -> Int -> String -> (Result Http.Error (List Lead) -> msg) -> Cmd msg
fetchLeadsPage ctx offset query = authedRequest ctx "GET" ("/api/leads?limit=50&offset=" ++ String.fromInt offset ++ "&q=" ++ Url.percentEncode query) Nothing (D.list leadDecoder)

fetchClientsPage : Ctx -> Int -> String -> (Result Http.Error (List Client) -> msg) -> Cmd msg
fetchClientsPage ctx offset query = authedRequest ctx "GET" ("/api/clients?limit=50&offset=" ++ String.fromInt offset ++ "&q=" ++ Url.percentEncode query) Nothing (D.list clientDecoder)

fetchTasksPage : Ctx -> Int -> (Result Http.Error (List Task) -> msg) -> Cmd msg
fetchTasksPage ctx offset = authedRequest ctx "GET" ("/api/tasks?limit=50&offset=" ++ String.fromInt offset) Nothing (D.list taskDecoder)


fetchFilteredLeads : Ctx -> { a | q : String, fStage : String, fQuality : String, fSource : String, sortBy : String, sortAsc : Bool } -> Int -> (Result Http.Error (List Lead) -> msg) -> Cmd msg
fetchFilteredLeads ctx filters offset =
    let pick value = if value == "All" then "" else Url.percentEncode value in
    authedRequest ctx "GET" ("/api/leads?limit=50&offset=" ++ String.fromInt offset ++ "&q=" ++ Url.percentEncode filters.q ++ "&stage=" ++ pick filters.fStage ++ "&quality=" ++ pick filters.fQuality ++ "&source=" ++ pick filters.fSource ++ "&sort=" ++ Url.percentEncode filters.sortBy ++ "&direction=" ++ (if filters.sortAsc then "asc" else "desc")) Nothing (D.list leadDecoder)

featureGet : Ctx -> String -> String -> Int -> (Result Http.Error D.Value -> msg) -> Cmd msg
featureGet ctx section query offset = authedRequest ctx "GET" ("/api/workspace/" ++ section ++ "?q=" ++ Url.percentEncode query ++ "&offset=" ++ String.fromInt offset) Nothing D.value

featurePost : Ctx -> String -> E.Value -> (Result Http.Error D.Value -> msg) -> Cmd msg
featurePost ctx path value = authedRequest ctx "POST" ("/api/workspace/" ++ path) (Just (Http.jsonBody value)) D.value

portalGet : Ctx -> (Result Http.Error D.Value -> msg) -> Cmd msg
portalGet ctx = authedRequest ctx "GET" "/api/portal" Nothing D.value

portalPost : Ctx -> String -> E.Value -> (Result Http.Error D.Value -> msg) -> Cmd msg
portalPost ctx action value = authedRequest ctx "POST" ("/api/portal/" ++ action) (Just (Http.jsonBody value)) D.value

portalUpload : Ctx -> Int -> File -> (Result Http.Error D.Value -> msg) -> Cmd msg
portalUpload ctx rid file = authedRequest ctx "POST" ("/api/portal/requests/" ++ String.fromInt rid ++ "/upload") (Just (Http.multipartBody [Http.filePart "file" file])) D.value

checklistUpload : Ctx -> Int -> Int -> File -> (Result Http.Error D.Value -> msg) -> Cmd msg
checklistUpload ctx rid revision file = authedRequest ctx "POST" ("/api/workspace/documents/" ++ String.fromInt rid ++ "/upload") (Just (Http.multipartBody [Http.filePart "file" file, Http.stringPart "expectedRevision" (String.fromInt revision)])) D.value

expectDetailed : (Result Http.Error a -> msg) -> D.Decoder a -> Http.Expect msg
expectDetailed toMsg decoder =
    Http.expectStringResponse toMsg (\response ->
        case response of
            Http.BadUrl_ url -> Err (Http.BadUrl url)
            Http.Timeout_ -> Err Http.Timeout
            Http.NetworkError_ -> Err Http.NetworkError
            Http.BadStatus_ metadata body ->
                if List.member metadata.statusCode [401,403,404,409,423,428,429] then Err (Http.BadStatus metadata.statusCode) else
                Err (Http.BadBody (D.decodeString (D.field "error" D.string) body |> Result.withDefault ("Request failed (" ++ String.fromInt metadata.statusCode ++ ")") |> String.left 240))
            Http.GoodStatus_ _ body -> D.decodeString decoder body |> Result.mapError (D.errorToString >> Http.BadBody)
    )
