module Route.Login exposing (ActionData, Data, Model, Msg, route)

import DataSource exposing (DataSource)
import ErrorPage exposing (ErrorPage)
import Form
import Form.Field as Field
import Form.Validation as Validation
import Head
import Head.Seo as Seo
import Html.Styled as Html exposing (Html)
import Html.Styled.Attributes as Attr
import MySession
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Result.Extra
import Route
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Server.Session as Session
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


type alias ActionData =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = \_ -> Request.skip ""
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    { username : Maybe String
    , flashMessage : Maybe String
    }


form =
    Form.init
        (\bar ->
            Validation.succeed identity
                |> Validation.withField bar
        )
        (\_ _ -> ())
        |> Form.field "name" (Field.text |> Field.required "Required")


data : RouteParams -> Request.Parser (DataSource (Response Data ErrorPage))
data routeParams =
    Request.oneOf
        [ MySession.withSession
            (Request.formDataWithoutServerValidation [ form ])
            (\nameResult session ->
                (nameResult
                    |> Result.Extra.unpack
                        (\_ ->
                            ( session
                                |> Result.withDefault Nothing
                                |> Maybe.withDefault Session.empty
                            , Route.redirectTo Route.Greet
                            )
                        )
                        (\name ->
                            ( session
                                |> Result.withDefault Nothing
                                |> Maybe.withDefault Session.empty
                                |> Session.insert "name" name
                                |> Session.withFlash "message" ("Welcome " ++ name ++ "!")
                            , Route.redirectTo Route.Greet
                            )
                        )
                )
                    |> DataSource.succeed
            )
        , MySession.withSession
            (Request.succeed ())
            (\() session ->
                case session of
                    Ok (Just okSession) ->
                        let
                            flashMessage : Maybe String
                            flashMessage =
                                okSession
                                    |> Session.get "message"
                        in
                        ( okSession
                        , Data
                            (okSession |> Session.get "name")
                            flashMessage
                            |> Response.render
                        )
                            |> DataSource.succeed

                    _ ->
                        ( Session.empty
                        , { username = Nothing, flashMessage = Nothing }
                            |> Response.render
                        )
                            |> DataSource.succeed
            )
        ]


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
view maybeUrl sharedModel static =
    { title = "Login"
    , body =
        [ static.data.flashMessage
            |> Maybe.map (\message -> flashView (Ok message))
            |> Maybe.withDefault (Html.p [] [ Html.text "No flash" ])
        , Html.p []
            [ Html.text
                (case static.data.username of
                    Just username ->
                        "Hello " ++ username ++ "!"

                    Nothing ->
                        "You aren't logged in yet."
                )
            ]
        , Html.form
            [ Attr.method "post"
            ]
            [ Html.label
                [ Attr.attribute "htmlFor" "name"
                ]
                [ Html.text "Name"
                , Html.input
                    [ Attr.name "name"
                    , Attr.type_ "text"
                    , Attr.id "name"
                    ]
                    []
                ]
            , Html.button
                [ Attr.type_ "submit"
                ]
                [ Html.text "Login" ]
            ]
        ]
    }


flashView : Result String String -> Html msg
flashView message =
    Html.p
        [ Attr.style "background-color" "rgb(163 251 163)"
        ]
        [ Html.text <|
            case message of
                Ok okMessage ->
                    okMessage

                Err error ->
                    "Something went wrong: " ++ error
        ]
