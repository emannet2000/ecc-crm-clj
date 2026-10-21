module Ui exposing
    ( icon
    , avatar
    , initials
    , emptyState
    , spinner
    , modal
    , qualityTag
    , stageTag
    , statusTag
    , priorityBadge
    , fmtDate
    , fmtDateTime
    , inputField
    , selectField
    , emptyNote
    )

{-| Small shared view helpers.
-}

import Html exposing (Html, div, span, text)
import Html.Attributes exposing (class, placeholder, selected, type_, value)
import Html.Events exposing (onInput)
import VirtualDom


spinner : Html msg
spinner =
    div [ class "loading-state", Html.Attributes.attribute "role" "status", Html.Attributes.attribute "aria-live" "polite" ]
        [ span [ class "spinner", Html.Attributes.attribute "aria-hidden" "true" ] []
        , span [] [ text "Loading your workspace…" ]
        ]


modal : String -> Html msg -> Html msg
modal title content =
    div [ class "modal-overlay" ]
        [ div [ class "modal-content", Html.Attributes.attribute "role" "dialog", Html.Attributes.attribute "aria-modal" "true", Html.Attributes.attribute "aria-label" title, Html.Attributes.tabindex -1 ]
            [ div [ class "section-head" ]
                [ Html.h3 [] [ text title ]
                ]
            , content
            ]
        ]


qualityTag : Maybe String -> Html msg
qualityTag q =
    case q of
        Just quality ->
            let
                cls =
                    case String.toLower quality of
                        "hot" -> "tag tag-hot"

                        "warm" -> "tag tag-warm"

                        "cold" -> "tag tag-cold"

                        _ -> "tag tag-cold"
            in
            span [ class cls ] [ text quality ]

        Nothing ->
            span [] []


stageClass : String -> String
stageClass stage =
    case stage of
        "Converted" -> "tag tag-converted"

        "Closed/Lost" -> "tag tag-lost"

        _ -> "tag tag-stage-blue"


stageTag : String -> Html msg
stageTag stage =
    span [ class (stageClass stage) ] [ text stage ]


statusTag : String -> Html msg
statusTag status =
    let
        cls =
            case status of
                "Done" -> "task-status Done"

                "In Progress" -> "task-status task-progress tag-progress"

                _ -> "task-status Pending"
    in
    span [ class cls ] [ text status ]


priorityBadge : String -> Html msg
priorityBadge priority =
    span [ class ("task-priority-badge " ++ String.toLower priority) ]
        [ text priority ]


fmtDate : Maybe String -> String
fmtDate md =
    Maybe.map (String.left 10) md |> Maybe.withDefault "—"


fmtDateTime : String -> String
fmtDateTime iso =
    String.slice 0 10 iso


inputField : String -> String -> String -> (String -> msg) -> Html msg
inputField label val typ onInputMsg =
    div [ class "form-group" ]
        [ Html.label [ Html.Attributes.for ("field-" ++ String.toLower (String.replace " " "-" label)) ] [ text label ]
        , Html.input
            [ Html.Attributes.id ("field-" ++ String.toLower (String.replace " " "-" label))
            , Html.Attributes.attribute "autocomplete" (if typ == "password" then "current-password" else if typ == "email" then "email" else "off")
            , type_ typ
            , class "input"
            , value val
            , onInput onInputMsg
            ]
            []
        ]


selectField :
    String
    -> List String
    -> String
    -> (String -> msg)
    -> Html msg
selectField label opts current onInputMsg =
    div [ class "form-group" ]
        [ Html.label [ Html.Attributes.for ("field-" ++ String.toLower (String.replace " " "-" label)) ] [ text label ]
        , Html.select [ onInput onInputMsg ]
            (List.map
                (\o ->
                    Html.option
                        [ Html.Attributes.value o
                        , selected (o == current)
                        ]
                        [ text o ]
                )
                opts
            )
        ]


emptyNote : String -> Html msg
emptyNote msg =
    div [ class "empty-note" ] [ text msg ]


icon : String -> Html msg
icon name =
    let
        paths = case name of
            "dashboard" -> [ "M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h7v7h-7z" ]
            "leads" -> [ "M4 4h16v4l-6 6v6l-4-2v-4L4 8z" ]
            "clients" -> [ "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M16 3a4 4 0 0 1 0 8M22 21v-2a4 4 0 0 0-3-3.87", "M13 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0" ]
            "tasks" -> [ "M9 5H5v16h14V5h-4M9 3h6v4H9zM8 12l2 2 6-5M8 18h8" ]
            "reminders" -> [ "M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4" ]
            "duplicates" -> [ "M9 9h12v12H9zM15 5V3H3v12h2" ]
            "archive" -> [ "M3 3h18v5H3zM5 8v13h14V8M10 12h4" ]
            "system" -> [ "M3 12h4l3-8 4 16 3-8h4" ]
            "audit" -> [ "M14 2H6v20h12V6zM14 2v5h5M9 12h6M9 16h6" ]
            "search" -> [ "M21 21l-5-5", "M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0" ]
            "arrow" -> [ "M5 12h14M13 6l6 6-6 6" ]
            "clock" -> [ "M12 8v5l3 2", "M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0" ]
            "check" -> [ "M5 12l4 4L19 6" ]
            "plus" -> [ "M12 5v14M5 12h14" ]
            _ -> [ "M12 3v18M3 12h18" ]
    in
    VirtualDom.nodeNS "http://www.w3.org/2000/svg" "svg"
        [ Html.Attributes.attribute "viewBox" "0 0 24 24"
        , Html.Attributes.attribute "width" "18"
        , Html.Attributes.attribute "height" "18"
        , Html.Attributes.attribute "fill" "none"
        , Html.Attributes.attribute "stroke" "currentColor"
        , Html.Attributes.attribute "stroke-width" "1.6"
        , Html.Attributes.attribute "stroke-linecap" "round"
        , Html.Attributes.attribute "stroke-linejoin" "round"
        , Html.Attributes.attribute "aria-hidden" "true"
        , Html.Attributes.attribute "focusable" "false"
        , Html.Attributes.attribute "class" "ui-icon"
        ]
        (List.map (\path -> VirtualDom.nodeNS "http://www.w3.org/2000/svg" "path" [ Html.Attributes.attribute "d" path ] []) paths)


initials : String -> String
initials name =
    name |> String.words |> List.take 2 |> List.map (String.left 1) |> String.concat |> String.toUpper


avatar : String -> Html msg
avatar name =
    span [ class "avatar", Html.Attributes.attribute "aria-hidden" "true" ] [ text (initials name) ]


emptyState : String -> String -> String -> Html msg
emptyState symbol title description =
    div [ class "empty-state" ]
        [ div [ class "empty-state-icon" ] [ icon symbol ]
        , Html.h3 [] [ text title ]
        , Html.p [] [ text description ]
        ]
