module Route.PasswordConfirmation exposing (ActionData, Data, Model, Msg, route)

import DataSource exposing (DataSource)
import Dict
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Form
import Form.Field as Field
import Form.FieldView
import Form.Validation as Validation exposing (Validation)
import Head
import Html exposing (Html)
import Html.Attributes as Attr
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Path exposing (Path)
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Shared
import View exposing (View)


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    {}


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = action
        }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , update = update
            , subscriptions = subscriptions
            , init = init
            }


init :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( {}, Effect.none )


update :
    PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update pageUrl sharedModel static msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
    Sub.none


type alias Data =
    {}


type alias ActionData =
    {}


data : RouteParams -> Request.Parser (DataSource (Response Data ErrorPage))
data routeParams =
    Request.succeed (DataSource.succeed (Response.render Data))


action : RouteParams -> Request.Parser (DataSource (Response ActionData ErrorPage))
action routeParams =
    Request.formDataWithoutServerValidation [ dependentParser ]
        |> Request.map
            (\parsedForm ->
                let
                    _ =
                        Debug.log "parsedForm" parsedForm
                in
                DataSource.succeed
                    (Response.render ActionData)
            )


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    []


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel model app =
    { title = "Dependent Form Example"
    , body =
        [ Html.h2 [] [ Html.text "Example" ]
        , dependentParser
            |> Form.toDynamicTransition "form"
            |> Form.renderHtml []
                -- TODO pass in form response from ActionData
                Nothing
                app
                ()
        ]
    }


type PostAction
    = ParsedLink String
    | ParsedPost { title : String, body : Maybe String }


type alias Validated =
    { username : String, password : String }


dependentParser : Form.HtmlForm String { username : String, password : String } data Msg
dependentParser =
    Form.init
        (\username password passwordConfirmation ->
            username
                |> Validation.map Validated
                |> Validation.andMap
                    (Validation.map2
                        (\passwordValue passwordConfirmationValue ->
                            if passwordValue == passwordConfirmationValue then
                                Validation.succeed passwordValue

                            else
                                Validation.fail passwordConfirmation "Must match password"
                        )
                        password
                        passwordConfirmation
                        |> Validation.andThen identity
                    )
        )
        (\formState username password passwordConfirmation ->
            [ fieldView formState "Username" username
            , fieldView formState "Password" password
            , fieldView formState "Password Confirmation" passwordConfirmation
            ]
        )
        |> Form.field "username" (Field.text |> Field.required "Required")
        |> Form.field "password" (Field.text |> Field.password |> Field.required "Required")
        |> Form.field "password-confirmation" (Field.text |> Field.password |> Field.required "Required")


fieldView :
    Form.Context String data
    -> String
    -> Form.ViewField String parsed Form.FieldView.Input
    -> Html msg
fieldView formState label field =
    let
        errorsView : Html msg
        errorsView =
            (if formState.submitAttempted || True then
                formState.errors
                    |> Form.errorsForField field
                    |> List.map (\error -> Html.li [] [ Html.text error ])

             else
                []
            )
                |> Html.ul [ Attr.style "color" "red" ]
    in
    Html.div []
        [ Html.label []
            [ Html.text (label ++ " ")
            , field |> Form.FieldView.input []
            ]
        , errorsView
        ]


type PostKind
    = Link
    | Post
