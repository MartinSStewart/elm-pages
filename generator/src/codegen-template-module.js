const fs = require("./dir-helpers.js");
const path = require("path");
const routeHelpers = require("./route-codegen-helpers");

async function run({ moduleName, withState, serverless }) {
  console.log("@@@ serverless");
  if (!moduleName.match(/[A-Z][A-Za-z0-9]+(\.[A-Z][A-Za-z0-9])*/)) {
    console.error("Invalid module name.");
    process.exit(1);
  }
  const content = fileContent(moduleName, withState, serverless);
  const fullFilePath = path.join(
    `src/Page/`,
    moduleName.replace(/\./g, "/") + ".elm"
  );
  await fs.tryMkdir(path.dirname(fullFilePath));
  fs.writeFile(fullFilePath, content);
}

/**
 * @param {string} pageModuleName
 * @param {'local' | 'shared' | null} withState
 * @param {boolean} serverless
 */
function fileContent(pageModuleName, withState, serverless) {
  return fileContentWithParams(
    pageModuleName,
    routeHelpers.routeParams(pageModuleName.split(".")).length > 0,
    withState,
    serverless
  );
}

/**
 * @param {string} pageModuleName
 * @param {boolean} withParams
 * @param {'local' | 'shared' | null} withState
 * @param {boolean} serverless
 */
function fileContentWithParams(
  pageModuleName,
  withParams,
  withState,
  serverless
) {
  return `module Page.${pageModuleName} exposing (Model, Msg, Data, page)

${withState ? "\nimport Browser.Navigation" : ""}
import DataSource exposing (DataSource)
import Head
import Head.Seo as Seo
import Page exposing (Page, PageWithState, StaticPayload)
${serverless ? "import PageServerResponse exposing (PageServerResponse)" : ""}
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Shared
${withState ? "import Path exposing (Path)\n" : ""}
import View exposing (View)


type alias Model =
    ${withState ? "{}" : "{}"}


${
  withState
    ? `type Msg
    = NoOp`
    : `type alias Msg =
    Never`
}

type alias RouteParams =
    ${routeHelpers.paramsRecord(pageModuleName.split("."))}

page : ${
    withState
      ? "PageWithState RouteParams Data Model Msg"
      : "Page RouteParams Data"
  }
page =
    ${
      serverless
        ? `Page.serverless
        { head = head
        , data = data
        }`
        : withParams
        ? `Page.prerender
        { head = head
        , pages = pages
        , data = data
        }`
        : `Page.single
        { head = head
        , data = data
        }`
    }
        |> ${
          withState
            ? `Page.buildWithLocalState
            { view = view
            , update = update
            , subscriptions = subscriptions
            , init = init
            }`
            : `Page.buildNoState { view = view }`
        }

${
  withState
    ? `
init :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> ( Model, Cmd Msg )
init maybePageUrl sharedModel static =
    ( {}, Cmd.none )


update :
    PageUrl
    -> Maybe Browser.Navigation.Key
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> Msg
    -> Model
    -> ${
      withState === "local"
        ? "( Model, Cmd Msg )"
        : "( Model, Cmd Msg, Maybe Shared.Msg )"
    }
update pageUrl maybeNavigationKey sharedModel static msg model =
    case msg of
        NoOp ->
            ${
              withState === "local"
                ? "( model, Cmd.none )"
                : "( model, Cmd.none, Nothing )"
            }


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path model =
    Sub.none
`
    : ""
}

${
  withParams
    ? `pages : DataSource (List RouteParams)
pages =
    DataSource.succeed []


`
    : ""
}
${
  serverless
    ? `data : Page.CanReadServerRequest -> RouteParams -> DataSource (PageServerResponse Data)
data serverRequestKey routeParams =`
    : withParams
    ? `data : RouteParams -> DataSource Data
data routeParams =`
    : `data : DataSource Data
data =`
}
    ${
      serverless
        ? `DataSource.succeed (PageServerResponse.RenderPage {})`
        : `DataSource.succeed {}`
    }

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


${
  withState
    ? `view :
    Maybe PageUrl
    -> Shared.Model
    -> templateModel
    -> StaticPayload templateData routeParams
    -> View templateMsg
view maybeUrl sharedModel model static =
`
    : `view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> View Msg
view maybeUrl sharedModel static =`
}
    View.placeholder "${pageModuleName}"
`;
}

module.exports = { run };
