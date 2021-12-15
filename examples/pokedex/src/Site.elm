module Site exposing (config)

import DataSource
import Head
import Pages.Manifest as Manifest
import Route exposing (Route)
import SiteConfig exposing (SiteConfig)
import Sitemap


type alias Data =
    ()


config : SiteConfig Data
config =
    { data = data
    , canonicalUrl = "https://elm-pages.com"
    , manifest = manifest
    , head = head
    }


data : DataSource.DataSource Data
data =
    DataSource.succeed ()


head : Data -> List Head.Tag
head static =
    [ Head.sitemapLink "/sitemap.xml"
    ]


manifest : Data -> Manifest.Config
manifest static =
    Manifest.init
        { name = "Site Name"
        , description = "Description"
        , startUrl = Route.Index |> Route.toPath
        , icons = []
        }


siteMap :
    List (Maybe Route)
    -> { path : List String, content : String }
siteMap allRoutes =
    allRoutes
        |> List.filterMap identity
        |> List.map
            (\route ->
                { path = Route.routeToPath route |> String.join "/"
                , lastMod = Nothing
                }
            )
        |> Sitemap.build { siteUrl = "https://elm-pages.com" }
        |> (\sitemapXmlString -> { path = [ "sitemap.xml" ], content = sitemapXmlString })
