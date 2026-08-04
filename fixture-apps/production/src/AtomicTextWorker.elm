port module AtomicTextWorker exposing (main)

import Json.Decode as Decode
import Json.Encode as Encode
import Platform
import Process
import Schelm.Node.FileSystem.AtomicText as AtomicText
import Task


port report : Encode.Value -> Cmd msg


type Msg
    = Finished (Result AtomicText.ReplaceFailure AtomicText.ReplaceResult)


type alias Flags =
    { root : String, segments : List String, text : String }


main : Program Flags () Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = always Sub.none
        }


init : Flags -> ( (), Cmd Msg )
init flags =
    case ( AtomicText.cooperativeRoot flags.root, AtomicText.relativeFile flags.segments ) of
        ( Ok root, Ok file ) ->
            ( ()
            , Process.sleep 0
                |> Task.andThen (always (AtomicText.replace root file flags.text))
                |> Task.attempt Finished
            )

        _ ->
            ( (), report (Encode.object [ ( "kind", Encode.string "invalid-flags" ) ]) )


update : Msg -> () -> ( (), Cmd Msg )
update (Finished result) model =
    ( model
    , report
        (case result of
            Ok _ ->
                Encode.object [ ( "kind", Encode.string "success" ) ]

            Err failure ->
                Encode.object
                    [ ( "kind", Encode.string "failure" )
                    , ( "phase", Encode.string "failed" )
                    ]
        )
    )
