module Page.Slide exposing (Data, Model, Msg, page)

import DataSource
import Head
import Head.Seo as Seo
import RouteBuilder exposing (StatelessRoute, StatefulRoute, StaticPayload)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    Never


type alias RouteParams =
    {}


page : StatelessRoute RouteParams Data
page =
    RouteBuilder.single
        { head = head
        , data = DataSource.succeed {}
        }
        |> RouteBuilder.buildNoState { view = view }


head :
    StaticPayload Data RouteParams
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


type alias Data =
    {}


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> View Msg
view maybeUrl sharedModel static =
    { title = "TODO title"
    , body = []
    }
