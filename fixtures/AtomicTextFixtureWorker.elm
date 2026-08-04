port module AtomicTextFixtureWorker exposing (main)

import Json.Decode as Decode
import Json.Encode as Encode
import Platform
import Process
import Schelm.Node.FileSystem.AtomicTextFixture as Fixture
import Task


port report : Encode.Value -> Cmd msg


port fixtureEventIn : (Decode.Value -> msg) -> Sub msg


port phase : Encode.Value -> Cmd msg


port fixtureAckIn : (Decode.Value -> msg) -> Sub msg


port actionOut : Encode.Value -> Cmd msg


port ackAccepted : Encode.Value -> Cmd msg


type Msg
    = Begin
    | FixtureEvent Decode.Value
    | FixtureAck Decode.Value
    | Finished (Result RawFailure RawOutcome)


type alias RawFailure =
    { phase : String, error : { kind : String, code : String, message : String }, residue : List String }


type alias RawOutcome =
    { durability : String, stage : String, error : { kind : String, code : String, message : String }, residue : List String }


type alias Flags =
    { root : String, segments : List String, text : String }


type alias Model =
    { flags : Flags }


main : Program Flags Model Msg
main =
    Platform.worker
        { init = \flags -> ( { flags = flags }, Task.perform (always Begin) (Process.sleep 0) )
        , update = update
        , subscriptions = \_ -> Sub.batch [ fixtureEventIn FixtureEvent, fixtureAckIn FixtureAck ]
        }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Begin ->
            ( model, Task.attempt Finished (Fixture.replace model.flags.root model.flags.segments model.flags.text) )

        FixtureEvent value ->
            ( model, phase value )

        FixtureAck value ->
            ( model, Cmd.batch [ ackAccepted value, actionOut value ] )

        Finished result ->
            ( model
            , report
                (Encode.object
                    [ ( "kind", Encode.string "result" )
                    , ( "ok", Encode.bool (Result.toMaybe result /= Nothing) )
                    ]
                )
            )
