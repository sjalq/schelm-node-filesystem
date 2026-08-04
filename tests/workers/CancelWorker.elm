port module CancelWorker exposing (main)

import Json.Encode as Encode
import Platform
import Process
import Schelm.Node.FileSystem.AtomicText as AtomicText
import Task


port report : Encode.Value -> Cmd msg


type Msg
    = Spawned (Result Never (Process.Id Msg))
    | KillNow
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
        , subscriptions = always Sub.none
        }


init : Flags -> ( Model, Cmd Msg )
init flags =
    case ( AtomicText.cooperativeRoot flags.root, AtomicText.relativeFile flags.segments ) of
        ( Ok root, Ok file ) ->
            ( { process = Nothing }
            , AtomicText.replace root file flags.text
                |> Task.attempt (always UnexpectedCompletion)
                |> Process.spawn
                |> Task.attempt Spawned
            )

        _ ->
            ( { process = Nothing }, report (Encode.string "invalid-flags") )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Spawned (Ok process) ->
            ( { process = Just process }
            , Cmd.batch
                [ report (Encode.string "spawned")
                , Task.perform (always KillNow) (Process.sleep 0)
                ]
            )

        Spawned (Err never) ->
            never

        KillNow ->
            case model.process of
                Just process ->
                    ( model, Task.perform (always Killed) (Process.kill process) )

                Nothing ->
                    ( model, Cmd.none )

        Killed ->
            ( model, report (Encode.string "killed") )

        UnexpectedCompletion ->
            ( model, report (Encode.string "unexpected-completion") )
