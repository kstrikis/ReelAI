Generate an audio (Stable Audio)
Overview
High-Quality Music Generation: Create music tracks based on descriptive prompts.

Flexible Integration: Compatible with various programming languages and frameworks.

Consumption
1 audio file will be generated for each request, consuming a total of 252 AI/ML Tokens per step.

API Reference
Generate audio using audio models.
Generates audio based on a text prompt using audio models, useful for creating audio content or responses.

post
/v2/generate/audio

Test it
Body
prompt
string
model
enum
Options: stable-audio
seconds_start
number
The start point of the audio clip to generate

seconds_total
number
The duration of the audio clip to generate

steps
number
The number of steps to denoise the audio

Responses

201
cURL
JavaScript
Python
HTTP
Copy
curl -L \
  --request POST \
  --url 'https://api.aimlapi.com/v2/generate/audio' \
  --header 'Content-Type: application/json' \
  --data '{"prompt":"text","model":"stable-audio","seconds_total":30,"steps":100}'
201
Copy
{
  "generation_id": "text"
}
Examples
JavaScript
Python
Copy
const main = async () => {
  const response = await fetch('https://api.aimlapi.com/v2/generate/audio', {
    method: 'POST',
    headers: {
      Authorization: 'Bearer <YOUR_API_KEY>',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'stable-audio',
      prompt: 'lo-fi pop hip-hop ambient music',
      steps: 100,
      seconds_total: 10,
    }),
  }).then((res) => res.json());

  console.log('Generation:', response);
};

main();

Example response:

{
  id: 'e6dcf61f-d3e5-4062-95e8-8b8fd0031cad:stable-audio',
  status: 'queued'
}

~~~

Fetch an audio (Stable Audio)
API Reference
get
/v2/generate/audio

Test it

Authorizations
Query parameters
Audio.v2.PollGenerationPayloadDTO
object

Show child attributes
Responses

default
cURL
JavaScript
Python
HTTP
Copy
curl -L \
  --url 'https://api.aimlapi.com/v2/generate/audio?Audio.v2.PollGenerationPayloadDTO=%5Bobject+Object%5D' \
  --header 'Authorization: Bearer JWT'
default
Copy
{
  "id": "text",
  "error": null,
  "status": "queued",
  "audio_file": {
    "url": "https://example.com"
  }
}
Examples
JavaScript
Python
Copy
const main = async () => {
  const params = new URLSearchParams({
    generation_id: "<YOUR_GENERATION_ID>"
  });
  const response = await fetch(`https://api.aimlapi.com/v2/generate/audio?${params.toString()}`, {
    method: 'GET',
    headers: {
      Authorization: 'Bearer <YOUR_API_KEY>',
      'Content-Type': 'application/json',
    },
  }).then((res) => res.json());

  console.log('Generation:', response);
};

main()

Example response:

{"id":"e6dcf61f-d3e5-4062-95e8-8b8fd0031cad:stable-audio","status":"completed","audio_file":{"url":"https://cdn.aimlapi.com/octopus/files/43647c7ac09c4d24944cb20734cd21f5_tmp1f_g_mml.wav","content_type":"application/octet-stream","file_name":"tmp1f_g_mml.wav","file_size":7938078}}%

~~~

Create speech
POST


https://api.elevenlabs.io
/v1/text-to-speech/:voice_id
Convert text to speech using our library of over 3,000 voices across 32 languages.

Path parameters
voice_id
string
Required
ID of the voice to be used. Use the Get voices endpoint list all the available voices.

Query parameters
enable_logging
boolean
Optional
Defaults to true
When enable_logging is set to false zero retention mode will be used for the request. This will mean history features are unavailable for this request, including request stitching. Zero retention mode may only be used by enterprise customers.

optimize_streaming_latency
integer
Optional
Deprecated
You can turn on latency optimizations at some cost of quality. The best possible final latency varies by model. Possible values: 0 - default mode (no latency optimizations) 1 - normal latency optimizations (about 50% of possible latency improvement of option 3) 2 - strong latency optimizations (about 75% of possible latency improvement of option 3) 3 - max latency optimizations 4 - max latency optimizations, but also with text normalizer turned off for even more latency savings (best latency, but can mispronounce eg numbers and dates).

Defaults to None.

output_format
enum
Optional
The output format of the generated audio.

mp3_22050_32
mp3_44100_32
mp3_44100_64
mp3_44100_96
mp3_44100_128
mp3_44100_192
pcm_16000
pcm_22050
pcm_24000
pcm_44100
ulaw_8000
Show 11 enum values
Request
This endpoint expects an object.
text
string
Required
The text that will get converted into speech.

model_id
string
Optional
Defaults to eleven_monolingual_v1
Identifier of the model that will be used, you can query them using GET /v1/models. The model needs to have support for text to speech, you can check this using the can_do_text_to_speech property.

language_code
string
Optional
Language code (ISO 639-1) used to enforce a language for the model. Currently only Turbo v2.5 and Flash v2.5 support language enforcement. For other models, an error will be returned if language code is provided.

voice_settings
object
Optional
Voice settings overriding stored setttings for the given voice. They are applied only on the given request.

stability
double
Optional
similarity_boost
double
Optional
style
double
Optional
Defaults to 0
use_speaker_boost
boolean
Optional
Defaults to true
Show 4 properties
pronunciation_dictionary_locators
list of objects
Optional
A list of pronunciation dictionary locators (id, version_id) to be applied to the text. They will be applied in order. You may have up to 3 locators per request


Show 2 properties
seed
integer
Optional
If specified, our system will make a best effort to sample deterministically, such that repeated requests with the same seed and parameters should return the same result. Determinism is not guaranteed. Must be integer between 0 and 4294967295.

previous_text
string
Optional
The text that came before the text of the current request. Can be used to improve the flow of prosody when concatenating together multiple generations or to influence the prosody in the current generation.

next_text
string
Optional
The text that comes after the text of the current request. Can be used to improve the flow of prosody when concatenating together multiple generations or to influence the prosody in the current generation.

previous_request_ids
list of strings
Optional
A list of request_id of the samples that were generated before this generation. Can be used to improve the flow of prosody when splitting up a large task into multiple requests. The results will be best when the same model is used across the generations. In case both previous_text and previous_request_ids is send, previous_text will be ignored. A maximum of 3 request_ids can be send.

next_request_ids
list of strings
Optional
A list of request_id of the samples that were generated before this generation. Can be used to improve the flow of prosody when splitting up a large task into multiple requests. The results will be best when the same model is used across the generations. In case both next_text and next_request_ids is send, next_text will be ignored. A maximum of 3 request_ids can be send.

use_pvc_as_ivc
boolean
Optional
Defaults to false
If true, we won’t use PVC version of the voice for the generation but the IVC version. This is a temporary workaround for higher latency in PVC versions.

apply_text_normalization
enum
Optional
Defaults to auto
Allowed values:
auto
on
off
This parameter controls text normalization with three modes: ‘auto’, ‘on’, and ‘off’. When set to ‘auto’, the system will automatically decide whether to apply text normalization (e.g., spelling out numbers). With ‘on’, text normalization will always be applied, while with ‘off’, it will be skipped. Cannot be turned on for ‘eleven_turbo_v2_5’ model.

Response
Successful Response

Errors

422
Text to Speech Convert Request Unprocessable Entity Error
Validation Error


Hide property
detail
list of objects
Optional

Hide 3 properties
loc
list of strings or integers

Hide 2 variants
abc
string or null
OR
123
integer or null
msg
string
type
string
POST

/v1/text-to-speech/:voice_id

Play

cURL

curl -X POST "https://api.elevenlabs.io/v1/text-to-speech/JBFqnCBsd6RMkjVDRZzb?output_format=mp3_44100_128" \
     -H "xi-api-key: <apiKey>" \
     -H "Content-Type: application/json" \
     -d '{
  "text": "The first move is what sets everything in motion.",
  "model_id": "eleven_multilingual_v2"
}'
422
Text to Speech Convert Request Unprocessable Entity Error

{}

~~~

Create sound effect
POST


https://api.elevenlabs.io
/v1/sound-generation
Turn text into sound effects for your videos, voice-overs or video games using the most advanced sound effects model in the world.

Request
This endpoint expects an object.
text
string
Required
The text that will get converted into a sound effect.

duration_seconds
double
Optional
The duration of the sound which will be generated in seconds. Must be at least 0.5 and at most 22. If set to None we will guess the optimal duration using the prompt. Defaults to None.

prompt_influence
double
Optional
Defaults to 0.3
A higher prompt influence makes your generation follow the prompt more closely while also making generations less variable. Must be a value between 0 and 1. Defaults to 0.3.

Response
Successful Response

Errors

422
Text to Sound Effects Convert Request Unprocessable Entity Error
POST

/v1/sound-generation

Play

cURL

curl -X POST https://api.elevenlabs.io/v1/sound-generation \
     -H "xi-api-key: <apiKey>" \
     -H "Content-Type: application/json" \
     -d '{
  "text": "Spacious braam suitable for high-impact movie trailer moments"
}'
