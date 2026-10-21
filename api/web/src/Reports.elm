module Reports exposing (view, payload)

import Dict
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput)
import Json.Decode as D
import Json.Encode as E
import State exposing (Model, Msg(..))

columns : String -> List (String, String)
columns kind =
    case kind of
        "ageing" -> [("title","Student / application"),("staff","Case officer"),("stage","Stage"),("ageDays","Age (days)"),("overdueDays","Overdue (days)")]
        "bottlenecks" -> [("title","Stage"),("cases","Applications"),("averageAgeDays","Average stage days"),("oldestDays","Oldest stage days")]
        "trends" -> [("date","Snapshot date"),("title","Staff member"),("openTasks","Open tasks"),("overdueTasks","Overdue tasks"),("openCases","Open applications")]
        _ -> [("title","Staff member"),("leads","Leads in cohort"),("converted","Converted leads"),("openTasks","Open tasks"),("overdueTasks","Overdue tasks"),("completedCases","Completed applications"),("averageCaseDays","Average application days")]

cell : String -> D.Value -> String
cell key row =
    D.decodeValue (D.field key (D.oneOf [D.string, D.map String.fromInt D.int, D.map String.fromFloat D.float, D.null "—"])) row |> Result.withDefault "—"

get : Model -> String -> String -> String
get model key fallback = Dict.get key model.reportSettings |> Maybe.withDefault fallback

visible : Model -> String -> List (String, String)
visible model kind = columns kind |> List.filter (\(key,_) -> get model (kind ++ ":hide:" ++ key) "false" /= "true")

reportRows : Model -> String -> List D.Value
reportRows model kind =
    let
        query = String.toLower (get model "filter" "")
        threshold = String.toFloat (get model "minimum" "") |> Maybe.withDefault 0
        metric = if List.member (get model "metric" "") (List.map Tuple.first (columns kind)) then get model "metric" "" else ""
        key = if List.member (get model "sort" "title") (List.map Tuple.first (columns kind)) then get model "sort" "title" else "title"
        compareRows a b =
            case (String.toFloat (cell key a), String.toFloat (cell key b)) of
                (Just x, Just y) -> compare x y
                _ -> compare (String.toLower (cell key a)) (String.toLower (cell key b))
        sorted = model.opsData
            |> List.filter (\row -> String.contains query (String.toLower (String.join " " (List.map (\(k,_) -> cell k row) (columns kind)))) && (metric == "" || (String.toFloat (cell metric row) |> Maybe.withDefault 0) >= threshold))
            |> List.sortWith compareRows
    in
    if get model "direction" "ascending" == "descending" then List.reverse sorted else sorted

payload : Model -> String -> String -> E.Value
payload model kind action =
    E.object
        [ ("action",E.string action)
        , ("title",E.string (get model "title" "ECC Management report"))
        , ("subtitle",E.string (get model "subtitle" ""))
        , ("footer",E.string (get model "footer" "Confidential · Internal use"))
        , ("paper",E.string (get model "paper" "A4"))
        , ("orientation",E.string (get model "orientation" "portrait"))
        , ("density",E.string (get model "density" "comfortable"))
        , ("range",E.string (if model.featureSearch == "" then (if kind == "reports" then "Last 30 days" else "All dates") else String.replace "," " to " model.featureSearch))
        , ("kind",E.string (case kind of
            "ageing" -> "Application ageing"
            "bottlenecks" -> "Application bottlenecks"
            "trends" -> "Historical workload"
            _ -> "Management summary"))
        , ("criteria",E.string ("Search: " ++ get model "filter" "All" ++ " · Minimum " ++ (columns kind |> List.filter (\(k,_) -> k == get model "metric" "") |> List.head |> Maybe.map Tuple.second |> Maybe.withDefault "(no numeric filter)") ++ ": " ++ get model "minimum" "0"))
        , ("headers",E.list (Tuple.second >> E.string) (visible model kind))
        , ("rows",E.list (\row -> E.list (\(key,_) -> E.string (cell key row)) (visible model kind)) (reportRows model kind))
        ]

view : Model -> String -> Html Msg
view model kind =
    let
        setting labelText key fallback = div [class "form-group"]
            [label [for ("report-" ++ key)] [text labelText],input [id ("report-" ++ key),class "input",value (get model key fallback),onInput (ReportSetting key)] []]
        choose labelText key fallback choices = div [class "form-group"]
            [label [for ("report-" ++ key)] [text labelText],select [id ("report-" ++ key),class "input",value (get model key fallback),onInput (ReportSetting key)] (List.map (\(v,l) -> option [value v,selected (v == get model key fallback)] [text l]) choices)]
        rows_ = reportRows model kind
        cols = visible model kind
    in
    section [class "report-designer card",attribute "aria-label" "Custom report designer"]
        [ h3 [] [text "Customize report and printing"]
        , p [class "status-help"] [text "Filter, sort and choose columns. Preview, CSV and printing use exactly the same rows and columns. Data is limited to 10,000 rows; narrow the date range when the limit is reached. Workload figures show the current position; trends use daily snapshots."]
        , div [class "report-controls"]
            [ setting "Report title" "title" "ECC Management report"
            , setting "Subtitle / organization" "subtitle" ""
            , setting "Find staff, student or stage" "filter" ""
            , choose "Sort by" "sort" "title" (columns kind)
            , choose "Sort direction" "direction" "ascending" [("ascending","Ascending"),("descending","Descending")]
            , choose "Numeric filter" "metric" "" (("","No numeric filter") :: List.filter (\(k,_) -> not (List.member k ["title","staff","stage","date"])) (columns kind))
            , setting "Minimum value (inclusive)" "minimum" "0"
            , choose "Paper" "paper" "A4" [("A4","A4"),("Letter","US Letter"),("Legal","US Legal")]
            , choose "Orientation" "orientation" "portrait" [("portrait","Portrait"),("landscape","Landscape")]
            , choose "Spacing" "density" "comfortable" [("comfortable","Comfortable"),("compact","Compact")]
            , setting "Footer note" "footer" "Confidential · Internal use"
            , div [class "form-group"] [label [for "report-logo"] [text "Header logo / picture (this session only)"],input [id "report-logo",type_ "file",accept "image/png,image/jpeg,image/webp"] [],button [type_ "button",class "btn btn-outline",attribute "data-clear-report-logo" ""] [text "Remove picture"]]
            ]
        , fieldset [class "report-columns"] (legend [] [text "Visible columns"] :: List.map (\(key,labelText) -> label [] [input [type_ "checkbox",checked (get model (kind ++ ":hide:" ++ key) "false" /= "true"),onClick (ReportSetting (kind ++ ":hide:" ++ key) (if get model (kind ++ ":hide:" ++ key) "false" == "true" then "false" else "true"))] [],text labelText]) (columns kind))
        , div [class "form-actions"]
            [ button [class "btn btn-primary",disabled (model.pageLoading || model.pageError /= "" || List.isEmpty cols || List.isEmpty rows_),onClick (ReportOutput "preview")] [text "Print preview / Save PDF"]
            , button [class "btn btn-outline",disabled (model.pageLoading || model.pageError /= "" || List.isEmpty cols || List.isEmpty rows_),onClick (ReportOutput "csv")] [text "Export customized CSV"]
            , button [class "btn btn-outline",onClick (ReportOutput "save-template")] [text "Save layout on this device"]
            , button [class "btn btn-outline",onClick (ReportOutput "load-template")] [text "Load saved layout"]
            ]
        , p [class "status-help",attribute "role" "status"] [text (if model.pageLoading then "Updating report…" else String.fromInt (List.length rows_) ++ " matching rows from " ++ String.fromInt (List.length model.opsData) ++ " loaded rows. Layout saving excludes report data, title, subtitle, search text, footer and pictures.")]
        , if List.length model.opsData >= 10000 then p [class "error-banner"] [text "10,000-row limit reached. Narrow the date range before printing or exporting."] else text ""
        , div [class "table-scroll report-table"] [table [class "data-table"] [thead [] [tr [] (List.map (\(_,l) -> th [] [text l]) cols)],tbody [] (List.map (\row -> tr [] (List.map (\(key,_) -> td [] [text (cell key row)]) cols)) (List.take 100 rows_))]]
        , if List.length rows_ > 100 then p [class "status-help"] [text "On-screen preview shows the first 100 matches. Print preview and customized CSV include all matches."] else text ""
        ]
