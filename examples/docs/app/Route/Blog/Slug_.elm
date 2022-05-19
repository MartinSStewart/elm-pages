module Route.Blog.Slug_ exposing (ActionData, Data, Model, Msg, route)

import Article
import Cloudinary
import Data.Author as Author exposing (Author)
import DataSource exposing (DataSource)
import Date exposing (Date)
import Head
import Head.Seo as Seo
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (css)
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Extra
import Markdown.Block
import Markdown.Renderer
import MarkdownCodec
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path
import RouteBuilder exposing (StatelessRoute, StaticPayload)
import Shared
import SiteOld
import StructuredData
import Tailwind.Breakpoints as Bp
import Tailwind.Utilities as Tw
import TailwindMarkdownRenderer
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    { slug : String }


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.preRender
        { data = data
        , head = head
        , pages = pages
        }
        |> RouteBuilder.buildNoState { view = view }


pages : DataSource.DataSource (List RouteParams)
pages =
    Article.blogPostsGlob
        |> DataSource.map
            (List.map
                (\globData ->
                    { slug = globData.slug }
                )
            )


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel static =
    { title = static.data.metadata.title
    , body =
        let
            author =
                Author.dillon
        in
        [ div
            [ css
                [ Tw.min_h_screen
                , Tw.w_full
                , Tw.relative
                ]
            ]
            [ div
                [ css
                    [ Tw.pt_16
                    , Tw.pb_16
                    , Tw.px_8
                    , Tw.flex
                    , Tw.flex_col
                    ]
                ]
                [ div
                    [ css
                        [ Bp.md [ Tw.mx_auto ]
                        ]
                    ]
                    [ h1
                        [ css
                            [ Tw.text_center
                            , Tw.text_4xl
                            , Tw.font_bold
                            , Tw.tracking_tight
                            , Tw.mt_2
                            , Tw.mb_8
                            ]
                        ]
                        [ text static.data.metadata.title
                        ]
                    , authorView author static.data
                    , div
                        [ css
                            [ Tw.prose
                            ]
                        ]
                        (static.data.body
                            |> Markdown.Renderer.render TailwindMarkdownRenderer.renderer
                            |> Result.withDefault []
                        )
                    ]
                ]
            ]
        ]
    }


authorView : Author -> Data -> Html msg
authorView author static =
    div
        [ css
            [ Tw.flex
            , Tw.mb_16

            --, Tw.flex_shrink_0
            ]
        ]
        [ img
            [ Attr.src (author.avatar |> Pages.Url.toString)
            , css
                [ Tw.rounded_full
                , Tw.h_10
                , Tw.w_10
                ]
            ]
            []
        , div
            [ css [ Tw.ml_3 ]
            ]
            [ div
                [ css
                    []
                ]
                [ p
                    [ css
                        [ Tw.text_sm
                        , Tw.font_medium
                        , Tw.text_gray_900
                        ]
                    ]
                    [ span
                        []
                        [ text author.name ]
                    ]
                ]
            , div
                [ css
                    [ Tw.flex
                    , Tw.space_x_1
                    , Tw.text_sm
                    , Tw.text_gray_500
                    , Tw.text_gray_400
                    ]
                ]
                [ time
                    [ Attr.datetime "2020-03-16"
                    ]
                    [ text (static.metadata.published |> Date.format "MMMM ddd, yyyy") ]
                ]
            ]
        ]


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    let
        metadata =
            static.data.metadata
    in
    Head.structuredData
        (StructuredData.article
            { title = metadata.title
            , description = metadata.description
            , author = StructuredData.person { name = Author.dillon.name }
            , publisher = StructuredData.person { name = Author.dillon.name }
            , url = SiteOld.canonicalUrl ++ Path.toAbsolute static.path
            , imageUrl = metadata.image
            , datePublished = Date.toIsoString metadata.published
            , mainEntityOfPage =
                StructuredData.softwareSourceCode
                    { codeRepositoryUrl = "https://github.com/dillonkearns/elm-pages"
                    , description = "A statically typed site generator for Elm."
                    , author = "Dillon Kearns"
                    , programmingLanguage = StructuredData.elmLang
                    }
            }
        )
        :: (Seo.summaryLarge
                { canonicalUrlOverride = Nothing
                , siteName = "elm-pages"
                , image =
                    { url = metadata.image
                    , alt = metadata.description
                    , dimensions = Nothing
                    , mimeType = Nothing
                    }
                , description = metadata.description
                , locale = Nothing
                , title = metadata.title
                }
                |> Seo.article
                    { tags = []
                    , section = Nothing
                    , publishedTime = Just (Date.toIsoString metadata.published)
                    , modifiedTime = Nothing
                    , expirationTime = Nothing
                    }
           )


type alias Data =
    { metadata : ArticleMetadata
    , body : List Markdown.Block.Block
    }


type alias ActionData =
    {}


data : RouteParams -> DataSource Data
data routeParams =
    MarkdownCodec.withFrontmatter Data
        frontmatterDecoder
        TailwindMarkdownRenderer.renderer
        ("content/blog/" ++ routeParams.slug ++ ".md")


type alias ArticleMetadata =
    { title : String
    , description : String
    , published : Date
    , image : Pages.Url.Url
    , draft : Bool
    }


frontmatterDecoder : Decoder ArticleMetadata
frontmatterDecoder =
    Decode.map5 ArticleMetadata
        (Decode.field "title" Decode.string)
        (Decode.field "description" Decode.string)
        (Decode.field "published"
            (Decode.string
                |> Decode.andThen
                    (\isoString ->
                        Date.fromIsoString isoString
                            |> Json.Decode.Extra.fromResult
                    )
            )
        )
        (Decode.field "image" imageDecoder)
        (Decode.field "draft" Decode.bool
            |> Decode.maybe
            |> Decode.map (Maybe.withDefault False)
        )


imageDecoder : Decode.Decoder Pages.Url.Url
imageDecoder =
    Decode.string
        |> Decode.map (\cloudinaryAsset -> Cloudinary.url cloudinaryAsset Nothing 800)
