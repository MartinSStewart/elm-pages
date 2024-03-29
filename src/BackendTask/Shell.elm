module BackendTask.Shell exposing
    ( Command
    , sh
    , command, exec
    , withTimeout
    , stdout, run, text
    , pipe
    , binary, tryJson, map, tryMap
    )

{-|

@docs Command


## Executing Commands

@docs sh

@docs command, exec

@docs withTimeout


## Capturing Output

@docs stdout, run, text


## Piping Commands

@docs pipe


## Output Decoders

@docs binary, tryJson, map, tryMap

-}

import BackendTask exposing (BackendTask)
import BackendTask.Http
import BackendTask.Internal.Request
import Base64
import Bytes exposing (Bytes)
import FatalError exposing (FatalError)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


command : String -> List String -> Command String
command command_ args =
    Command
        { command = [ subCommand command_ args ]
        , quiet = False
        , timeout = Nothing
        , decoder = Just
        , cwd = Nothing
        }


subCommand : String -> List String -> SubCommand
subCommand command_ args =
    { command = command_
    , args = args
    , timeout = Nothing
    }


type alias SubCommand =
    { command : String
    , args : List String
    , timeout : Maybe Int
    }


type Command stdout
    = Command
        { command : List SubCommand
        , quiet : Bool
        , timeout : Maybe Int
        , decoder : String -> Maybe stdout
        , cwd : Maybe String
        }


map : (a -> b) -> Command a -> Command b
map mapFn (Command command_) =
    Command
        { command = command_.command
        , quiet = command_.quiet
        , timeout = command_.timeout
        , decoder = command_.decoder >> Maybe.map mapFn
        , cwd = command_.cwd
        }


tryMap : (a -> Maybe b) -> Command a -> Command b
tryMap mapFn (Command command_) =
    Command
        { command = command_.command
        , quiet = command_.quiet
        , timeout = command_.timeout
        , decoder = command_.decoder >> Maybe.andThen mapFn
        , cwd = command_.cwd
        }


binary : Command String -> Command Bytes
binary (Command command_) =
    Command
        { command = command_.command
        , quiet = command_.quiet
        , timeout = command_.timeout
        , decoder = Base64.toBytes
        , cwd = command_.cwd
        }


{-| Applies to each individual command in the pipeline.
-}
withTimeout : Int -> Command stdout -> Command stdout
withTimeout timeout (Command command_) =
    Command { command_ | timeout = Just timeout }


text : Command stdout -> BackendTask FatalError String
text command_ =
    command_
        |> run
        |> BackendTask.map .stdout
        |> BackendTask.quiet
        |> BackendTask.allowFatal



--redirect : Command -> ???


stdout : Command stdout -> BackendTask FatalError stdout
stdout ((Command command_) as fullCommand) =
    fullCommand
        |> run
        |> BackendTask.quiet
        |> BackendTask.allowFatal
        |> BackendTask.andThen
            (\output ->
                case output.stdout |> command_.decoder of
                    Just okStdout ->
                        BackendTask.succeed okStdout

                    Nothing ->
                        -- TODO provide decoder error message here! Need Result instead of Maybe.
                        BackendTask.fail (FatalError.fromString "Decoder failed")
            )


pipe : Command to -> Command from -> Command to
pipe (Command to) (Command from) =
    Command
        { command = from.command ++ to.command
        , quiet = to.quiet
        , timeout = to.timeout
        , decoder = to.decoder
        , cwd =
            case to.cwd of
                Just cwd ->
                    Just cwd

                Nothing ->
                    from.cwd
        }


run :
    Command stdout
    ->
        BackendTask
            { fatal : FatalError
            , recoverable : { output : String, stderr : String, stdout : String, statusCode : Int }
            }
            { output : String, stderr : String, stdout : String }
run (Command options_) =
    shell__
        { commands = options_.command
        , cwd = options_.cwd
        }
        True


exec : Command stdout -> BackendTask FatalError ()
exec (Command options_) =
    shell__
        { commands = options_.command
        , cwd = options_.cwd
        }
        False
        |> BackendTask.allowFatal
        |> BackendTask.map (\_ -> ())


tryJson : Decoder a -> Command String -> Command a
tryJson jsonDecoder command_ =
    command_
        |> tryMap
            (\jsonString ->
                Decode.decodeString jsonDecoder jsonString
                    |> Result.toMaybe
            )


{-| -}
sh : String -> List String -> BackendTask FatalError ()
sh command_ args =
    command command_ args |> exec


{-| -}
shell__ :
    Command_
    -> Bool
    ->
        BackendTask
            { fatal : FatalError
            , recoverable :
                { output : String
                , stderr : String
                , stdout : String
                , statusCode : Int
                }
            }
            { output : String
            , stderr : String
            , stdout : String
            }
shell__ commandsAndArgs captureOutput =
    BackendTask.Internal.Request.request
        { name = "shell"
        , body = BackendTask.Http.jsonBody (commandsAndArgsEncoder commandsAndArgs captureOutput)
        , expect = BackendTask.Http.expectJson commandDecoder
        }
        |> BackendTask.andThen
            (\rawOutput ->
                if rawOutput.exitCode == 0 then
                    BackendTask.succeed
                        { output = rawOutput.output
                        , stderr = rawOutput.stderr
                        , stdout = rawOutput.stdout
                        }

                else
                    FatalError.recoverable { title = "Shell command error", body = "Exit status was " ++ String.fromInt rawOutput.exitCode }
                        { output = rawOutput.output
                        , stderr = rawOutput.stderr
                        , stdout = rawOutput.stdout
                        , statusCode = rawOutput.exitCode
                        }
                        |> BackendTask.fail
            )


type alias Command_ =
    { cwd : Maybe String
    , commands : List SubCommand
    }


commandsAndArgsEncoder : Command_ -> Bool -> Encode.Value
commandsAndArgsEncoder commandsAndArgs captureOutput =
    Encode.object
        [ ( "cwd", nullable Encode.string commandsAndArgs.cwd )
        , ( "captureOutput", Encode.bool captureOutput )
        , ( "commands"
          , Encode.list
                (\sub ->
                    Encode.object
                        [ ( "command", Encode.string sub.command )
                        , ( "args", Encode.list Encode.string sub.args )
                        , ( "timeout", sub.timeout |> nullable Encode.int )
                        ]
                )
                commandsAndArgs.commands
          )
        ]


nullable : (a -> Encode.Value) -> Maybe a -> Encode.Value
nullable encoder =
    Maybe.map encoder >> Maybe.withDefault Encode.null


type alias RawOutput =
    { exitCode : Int
    , output : String
    , stderr : String
    , stdout : String
    }


commandDecoder : Decoder RawOutput
commandDecoder =
    Decode.map4 RawOutput
        (Decode.field "errorCode" Decode.int)
        (Decode.field "output" Decode.string)
        (Decode.field "stderrOutput" Decode.string)
        (Decode.field "stdoutOutput" Decode.string)
