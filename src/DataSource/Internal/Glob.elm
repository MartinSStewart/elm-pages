module DataSource.Internal.Glob exposing
    ( Glob(..)
    , extractMatches
    , run
    , toPattern
    )

import List.Extra
import Regex exposing (Regex)


{-| -}
type Glob a
    = Glob String String (String -> List String -> ( a, List String ))


run : String -> List String -> Glob a -> { match : a, pattern : String }
run rawInput captures (Glob pattern regex applyCapture) =
    let
        fullRegex : String
        fullRegex =
            "^" ++ regex ++ "$"

        regexCaptures : List String
        regexCaptures =
            Regex.find parsedRegex rawInput
                |> List.concatMap .submatches
                |> List.map (Maybe.withDefault "")

        parsedRegex : Regex
        parsedRegex =
            Regex.fromString fullRegex |> Maybe.withDefault Regex.never
    in
    { match =
        captures
            |> List.reverse
            |> applyCapture rawInput
            |> Tuple.first
    , pattern = pattern
    }


{-| -}
toPattern : Glob a -> String
toPattern (Glob pattern _ _) =
    pattern


{-| -}
extractMatches : a -> List ( String, a ) -> String -> List a
extractMatches defaultValue list string =
    extractMatchesHelp defaultValue list string []


extractMatchesHelp : a -> List ( String, a ) -> String -> List a -> List a
extractMatchesHelp defaultValue list string soFar =
    if string == "" then
        List.reverse soFar

    else
        let
            ( matchedValue, updatedString ) =
                List.Extra.findMap
                    (\( literalString, value ) ->
                        if string |> String.startsWith literalString then
                            Just ( value, string |> String.dropLeft (String.length literalString) )

                        else
                            Nothing
                    )
                    list
                    |> Maybe.withDefault ( defaultValue, "" )
        in
        extractMatchesHelp defaultValue list updatedString (matchedValue :: soFar)
