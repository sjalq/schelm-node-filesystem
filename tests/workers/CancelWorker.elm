port module CancelWorker exposing (main)

import Json.Encode as Encode
import Platform
import Process
import Schelm.Node.FileSystem.AtomicTextFixture as Fixture
import Task


port report : Encode.Value -> Cmd msg


port command : (String -> msg) -> Sub msg


type Msg
    = Spawned (Result Never (Process.Id Msg))
    | Command String
    | Killed
    | UnexpectedCompletion


type alias Model =
    { process : Maybe (Process.Id Msg) }


type alias Flags =
    { root : String, segments : List String, text : String }


main : Program Flags Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = always (command Command)
        }


init : Flags -> ( Model, Cmd Msg )
init flags =
    if List.isEmpty flags.segments then
        ( { process = Nothing }, report (Encode.string "invalid-flags") )

    else
        ( { process = Nothing }
        , Fixture.replace flags.root flags.segments flags.text
            |> Task.attempt (always UnexpectedCompletion)
            |> Process.spawn
            |> Task.attempt Spawned
        )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Spawned (Ok process) ->
            ( { process = Just process }, report (Encode.string "spawned") )

        Spawned (Err never) ->
            never

        Command "kill" ->
            case model.process of
                Just process ->
                    ( model, Task.perform (always Killed) (Process.kill process) )

                Nothing ->
                    ( model, report (Encode.string "kill-before-spawn") )

        Command _ ->
            ( model, Cmd.none )

        Killed ->
            ( model, report (Encode.string "killed") )

        UnexpectedCompletion ->
            ( model, report (Encode.string "unexpected-completion") )
