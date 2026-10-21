module Operations exposing (view)
import Html exposing (Html, div, h2, h3, p, text, span, button, a)
import Html.Attributes exposing (class, href, disabled)
import Html.Events exposing (onClick)
import Json.Decode as D
import State exposing (..)
import Ui

str : String -> D.Value -> String
str key value = D.decodeValue (D.field key D.string) value |> Result.withDefault "—"
num : String -> D.Value -> Int
num key value = D.decodeValue (D.field key D.int) value |> Result.withDefault 0
flag : String -> D.Value -> Bool
flag key value = D.decodeValue (D.field key D.bool) value |> Result.withDefault False

view : Model -> String -> Html Msg
view model kind =
    let
        (title,description,empty) = case kind of
            "archive" -> ("Archive","Deleted leads and clients stay here with their history. Restore a record to continue working.","No archived records. Your workspace is up to date.")
            "duplicates" -> ("Possible duplicates","Review shared email addresses and phone numbers before creating another record.","No matching contacts found. Looking good.")
            "metrics" -> ("System overview","Delivery queue, database storage and active sessions. Failed email deliveries need attention.","No system information available.")
            _ -> ("Your reminders","Follow-ups and tasks due in the next seven days. Mark reminders as read without completing the underlying task.","You’re all caught up. No upcoming reminders.")
        row item = case kind of
            "archive" -> div [ class "operation-row" ]
                [ div [] [ span [ class "eyebrow" ] [ text (str "kind" item ++ " / " ++ str "number" item) ], h3 [] [ text (str "name" item) ], p [ class "text-muted" ] [ text ("Archived " ++ String.left 10 (str "date" item)) ] ]
                , button [ class "btn btn-outline", onClick (RunOperation ((if str "kind" item == "lead" then "leads/" else "clients/") ++ String.fromInt (num "id" item) ++ "/restore")) ] [ text "Restore record ↗" ]
                ]
            "duplicates" ->
                let records = D.decodeValue (D.field "records" (D.list D.value)) item |> Result.withDefault [] in
                div [ class "operation-row" ]
                    [ div [] [ span [ class "eyebrow" ] [ text ("MATCHING " ++ String.toUpper (str "field" item)) ], h3 [] [ text (str "value" item) ] ]
                    , div [ class "duplicate-links" ] (List.map (\record -> a [ class "btn btn-outline", href ((if str "kind" record == "lead" then "/leads/" else "/clients/") ++ String.fromInt (num "id" record)) ] [ text (str "name" record ++ " ↗") ]) records)
                    ]
            "metrics" -> div [ class "stats" ]
                [ metric "Pending emails" (num "pendingMail" item)
                , metric "Failed deliveries" (num "failedMail" item)
                , metric "Active sessions" (num "activeSessions" item)
                , metric "Database · MB" (num "databaseBytes" item // 1048576)
                ]
            _ -> div [ class (if flag "read" item then "operation-row reminder-read" else "operation-row") ]
                [ div [] [ span [ class "eyebrow" ] [ text (String.toUpper (str "kind" item) ++ " / DUE " ++ str "due" item) ], h3 [] [ a [ href (str "path" item) ] [ text (str "title" item) ] ] ]
                , button [ class "btn btn-outline", disabled (flag "read" item), onClick (RunOperation ("reminders/" ++ str "kind" item ++ "/" ++ String.fromInt (num "id" item) ++ "/read")) ] [ text (if flag "read" item then "✓ Read" else "Mark as read") ]
                ]
    in
    div []
        [ div [ class "page-head" ] [ div [] [ h2 [] [ text title ], p [ class "page-description" ] [ text description ] ], button [ class "btn btn-outline", onClick (NavigateTo model.url.path) ] [ text "Refresh ↻" ] ]
        , if model.pageLoading then Ui.spinner
          else if List.isEmpty model.opsData && model.pageError == "" then div [ class "empty-state card" ] [ div [ class "empty-state-icon" ] [ text "✓" ], h3 [] [ text empty ], p [] [ text "Everything you need will appear here." ] ]
          else div [ class "operations-list" ] (List.map row model.opsData)
        ]

metric : String -> Int -> Html Msg
metric label value = div [ class "stat" ] [ div [ class "stat-label" ] [ text label ], div [ class "stat-value" ] [ text (String.fromInt value) ] ]
