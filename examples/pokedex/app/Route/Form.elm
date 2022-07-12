module Route.Form exposing (ActionData, Data, Model, Msg, route)

import DataSource exposing (DataSource)
import Date exposing (Date)
import Dict exposing (Dict)
import ErrorPage exposing (ErrorPage)
import Form
import Form.Field as Field
import Form.FieldView
import Form.Validation as Validation
import Form.Value
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import RouteBuilder exposing (StatelessRoute, StaticPayload)
import Server.Request as Request exposing (Parser)
import Server.Response
import Shared
import Time
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


type alias ActionData =
    { user : User
    , formResponse : Maybe { fields : List ( String, String ), errors : Dict String (List String) }
    }


type alias User =
    { first : String
    , last : String
    , username : String
    , email : String
    , birthDay : Date
    , checkbox : Bool
    }


defaultUser : User
defaultUser =
    { first = "Jane"
    , last = "Doe"
    , username = "janedoe"
    , email = "janedoe@example.com"
    , birthDay = Date.fromCalendarDate 1969 Time.Jul 20
    , checkbox = False
    }


form : Form.HtmlForm String User User Msg
form =
    Form.init
        (\first last username email dob check ->
            Validation.succeed User
                |> Validation.andMap first
                |> Validation.andMap last
                |> Validation.andMap username
                |> Validation.andMap email
                |> Validation.andMap dob
                |> Validation.andMap check
        )
        (\formState firstName lastName username email dob check ->
            let
                errors field =
                    formState.errors
                        |> Form.errorsForField field

                errorsView field =
                    case ( formState.submitAttempted, field |> errors ) of
                        ( _, first :: rest ) ->
                            Html.div []
                                [ Html.ul
                                    [ Attr.style "border" "solid red"
                                    ]
                                    (List.map
                                        (\error ->
                                            Html.li []
                                                [ Html.text error
                                                ]
                                        )
                                        (first :: rest)
                                    )
                                ]

                        _ ->
                            Html.div [] []

                fieldView label field =
                    Html.div []
                        [ Html.label []
                            [ Html.text (label ++ " ")
                            , field |> Form.FieldView.input []
                            ]
                        , errorsView field
                        ]
            in
            [ fieldView "First" firstName
            , fieldView "Last" lastName
            , fieldView "Price" username
            , fieldView "Image" email
            , fieldView "Image" dob
            , Html.button []
                [ Html.text
                    (if formState.isTransitioning then
                        "Updating..."

                     else
                        "Update"
                    )
                ]
            ]
        )
        |> Form.field "first"
            (Field.text
                |> Field.required "Required"
                |> Field.withInitialValue (.first >> Form.Value.string)
            )
        |> Form.field "last"
            (Field.text
                |> Field.required "Required"
                |> Field.withInitialValue (.last >> Form.Value.string)
            )
        |> Form.field "username"
            (Field.text
                |> Field.required "Required"
                |> Field.withInitialValue (.username >> Form.Value.string)
             --|> Form.withServerValidation
             --    (\username ->
             --        if username == "asdf" then
             --            DataSource.succeed [ "username is taken" ]
             --
             --        else
             --            DataSource.succeed []
             --    )
            )
        |> Form.field "email"
            (Field.text
                |> Field.required "Required"
                |> Field.withInitialValue (.email >> Form.Value.string)
            )
        |> Form.field "dob"
            (Field.date
                { invalid = \_ -> "Invalid date"
                }
                |> Field.required "Required"
                |> Field.withInitialValue (.birthDay >> Form.Value.date)
             --|> Field.withMin (Date.fromCalendarDate 1900 Time.Jan 1 |> Form.Value.date)
             --|> Field.withMax (Date.fromCalendarDate 2022 Time.Jan 1 |> Form.Value.date)
            )
        |> Form.field "checkbox" Field.checkbox


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = action
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    {}


data : RouteParams -> Parser (DataSource (Server.Response.Response Data ErrorPage))
data routeParams =
    Data
        |> Server.Response.render
        |> DataSource.succeed
        |> Request.succeed


action : RouteParams -> Parser (DataSource (Server.Response.Response ActionData ErrorPage))
action routeParams =
    Request.formData [ form ]
        |> Request.map
            (\userResultData ->
                userResultData
                    |> DataSource.map
                        (\userResult ->
                            (case userResult of
                                Ok user ->
                                    { user = user
                                    , formResponse = Nothing
                                    }

                                Err error ->
                                    { user = defaultUser
                                    , formResponse = Just error
                                    }
                            )
                                |> Server.Response.render
                        )
            )


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = Pages.Url.external "TODO"
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "TODO"
        , locale = Nothing
        , title = "TODO title" -- metadata.title -- TODO
        }
        |> Seo.website


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel app =
    let
        user : User
        user =
            app.action
                |> Maybe.map .user
                |> Maybe.withDefault defaultUser
    in
    { title = "Form Example"
    , body =
        [ Html.pre []
            [ app.action
                |> Debug.toString
                |> Html.text
            ]
        , app.action
            |> Maybe.map .user
            |> Maybe.map
                (\user_ ->
                    Html.p
                        [ Attr.style "padding" "10px"
                        , Attr.style "background-color" "#a3fba3"
                        ]
                        [ Html.text <| "Successfully received user " ++ user_.first ++ " " ++ user_.last
                        ]
                )
            |> Maybe.withDefault (Html.p [] [])
        , Html.h1
            []
            [ Html.text <| "Edit profile " ++ user.first ++ " " ++ user.last ]
        , form
            |> Form.toDynamicTransition "test1"
            |> Form.renderHtml
                [ Attr.style "display" "flex"
                , Attr.style "flex-direction" "column"
                , Attr.style "gap" "20px"
                ]
                app
                defaultUser
        ]
    }
