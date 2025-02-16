// Environment variables are automatically loaded by Firebase Functions
import * as functions from "firebase-functions/v2";
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { ChatOpenAI } from "@langchain/openai";
import { ChatPromptTemplate, SystemMessagePromptTemplate, HumanMessagePromptTemplate } from "@langchain/core/prompts";
import { JsonOutputFunctionsParser } from "langchain/output_parsers";
import { RunnableSequence } from "@langchain/core/runnables";
import { z } from "zod";
import { HttpsError } from "firebase-functions/v2/https";
import fetch from "node-fetch";
import { Buffer } from "buffer";
import { setTimeout as sleep } from "timers/promises";
import { getStorage } from "firebase-admin/storage";
import ffmpeg from "fluent-ffmpeg";
import { createWriteStream } from "fs";
import { unlink } from "fs/promises";
import { tmpdir } from "os";
import { join } from "path";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

// Initialize Firebase Admin
initializeApp();
const db = getFirestore();

// Schema for story scene
const SceneSchema = z.object({
  id: z.string(),
  sceneNumber: z.number(),
  narration: z.string().optional(),
  voice: z.string().optional(),
  visualPrompt: z.string(),
  audioPrompt: z.string().optional(),
  duration: z.number().optional(),
});

// Schema for the complete story
const StorySchema = z.object({
  id: z.string(),
  title: z.string(),
  template: z.string(),
  backgroundMusicPrompt: z.string().optional(), // Story-wide background music prompt
  scenes: z.array(SceneSchema),
  createdAt: z.string(), // ISO date string
  userId: z.string(),
});

// Test function to verify prompt template functionality
export const testPrompt = functions.https.onRequest(async (request, response) => {
  if (!process.env.FUNCTIONS_EMULATOR) {
    response.status(404).send("Not available in production");
    return;
  }

  try {
    // Initialize components
    const model = new ChatOpenAI({
      modelName: "gpt-4-1106-preview",
      temperature: 0.7,
    });

    const systemTemplate = SystemMessagePromptTemplate.fromTemplate(
      "You are a helpful assistant that gives short, one-sentence answers."
    );
    const humanTemplate = HumanMessagePromptTemplate.fromTemplate(
      "Tell me a story about {topic}"
    );
    const formatPrompt = ChatPromptTemplate.fromMessages([
      systemTemplate,
      humanTemplate
    ]);

    // Define transformation steps
    const logPrompt = (promptValue) => {
      console.log("Formatted prompt:", promptValue);
      return promptValue;
    };

    const generateResponse = async (messages) => {
      return await model.invoke(messages);
    };

    const logOutput = (modelOutput) => {
      console.log("Model output:", modelOutput);
      return modelOutput;
    };

    // Compose the chain using RunnableSequence
    const chain = RunnableSequence.from([
      {
        formattedPrompt: formatPrompt
      },
      async (data) => {
        const promptValue = await data.formattedPrompt;
        return logPrompt(promptValue);
      },
      generateResponse,
      logOutput
    ]);

    const result = await chain.invoke({
      topic: "a dancing frog"
    });

    response.json({
      success: true,
      result: result
    });
  } catch (error) {
    console.error("Test prompt error:", error);
    response.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : "Unknown error occurred"
    });
  }
});

// Define the function schema for structured output
const storyFunctionSchema = {
  name: "create_story",
  description: "Create a multi-scene story based on a prompt",
  parameters: {
    type: "object",
    properties: {
      id: {
        type: "string",
        description: "Unique identifier for the story"
      },
      title: {
        type: "string",
        description: "A compelling title for the story"
      },
      template: {
        type: "string",
        description: "The template or theme used for the story"
      },
      backgroundMusicPrompt: {
        type: "string",
        description: "A prompt for generating background music that will play throughout the entire story"
      },
      scenes: {
        type: "array",
        description: "Array of scenes that make up the story",
        items: {
          type: "object",
          properties: {
            id: {
              type: "string",
              description: "Unique identifier for the scene"
            },
            sceneNumber: {
              type: "integer",
              description: "Order of the scene in the story (1-based)"
            },
            narration: {
              type: "string",
              description: "Text narration for this scene"
            },
            voice: {
              type: "string",
              description: "Voice style to use (e.g., 'ElevenLabs Adam', 'TikTok Voice 4')"
            },
            visualPrompt: {
              type: "string",
              description: "Detailed prompt for image/video generation"
            },
            audioPrompt: {
              type: "string",
              description: "Prompt for scene-specific sound effects or ambient sounds"
            },
            duration: {
              type: "number",
              description: "Estimated duration in seconds (between 3-10)"
            }
          },
          required: ["id", "sceneNumber", "visualPrompt"]
        }
      }
    },
    required: ["title", "scenes", "backgroundMusicPrompt"]
  }
};

// Create the story generation chain
const createStoryChain = () => {
  const model = new ChatOpenAI({
    modelName: "gpt-4-1106-preview",
    temperature: 0.8
  });

  const systemTemplate = SystemMessagePromptTemplate.fromTemplate(
    "You are a creative storyteller that specializes in creating engaging, multi-scene stories optimized for video generation. " +
    "Your mission is to create stories that are:\n" +
    "1. Visually compelling - each scene should paint a clear, vivid picture\n" +
    "2. Emotionally resonant - stories should connect with viewers on an emotional level\n" +
    "3. Social media optimized - perfect for short-form video platforms\n" +
    "4. Cohesive - scenes should flow naturally, maintaining viewer attention\n" +
    "5. Audio-rich - create both scene-specific sound effects and a cohesive background music prompt\n\n" +
    "Remember: These stories will be turned into engaging social media videos. Focus on:\n" +
    "- Visual impact and emotional connection\n" +
    "- Scene-specific sound effects that enhance each moment\n" +
    "- A background music prompt that ties the whole story together emotionally"
  );

  const formatPrompt = ChatPromptTemplate.fromMessages([
    systemTemplate,
    HumanMessagePromptTemplate.fromTemplate(
      "Create a story based on this prompt: {prompt}\n\n" +
      "Requirements:\n" +
      "1. Title: Create a compelling, memorable title that would work well as a video title\n" +
      "2. Scenes (3-5):\n" +
      "   - Narration: Clear, engaging text that drives the story forward (keep it concise for video)\n" +
      "   - Voice: Specify a voice style (e.g., \"ElevenLabs Brian\", \"ElevenLabs Adam\") that matches the scene's emotion\n" +
      "   - Visual: Detailed prompt for image/video generation - include style, mood, action, camera angles, and lighting\n" +
      "   - Audio: Specific prompt for scene-specific sound effects and ambient sounds that enhance the atmosphere\n" +
      "   - Duration: 3-10 seconds per scene (optimize for social media attention spans)\n\n" +
      "3. Background Music: Create a detailed prompt for generating continuous background music that:\n" +
      "   - Matches the overall emotional journey of the story\n" +
      "   - Complements but doesn't overpower scene-specific sounds\n" +
      "   - Has a clear style, tempo, and mood description\n" +
      "   - Can seamlessly play throughout the entire video\n\n" +
      "Make each scene visually striking and suitable for video generation. Focus on creating moments that will capture and maintain viewer attention.\n\n" +
      "Remember:\n" +
      "- Each scene should be visually distinct but maintain story coherence\n" +
      "- Scene-specific audio effects should enhance specific moments\n" +
      "- Background music should tie the whole story together emotionally\n" +
      "- Keep the overall story length optimal for social media (15-45 seconds total)"
    )
  ]);

  const outputParser = new JsonOutputFunctionsParser();

  const validateAndEnhanceOutput = (parsedOutput) => {
    if (!parsedOutput || !parsedOutput.title || !parsedOutput.scenes || !Array.isArray(parsedOutput.scenes)) {
      throw new Error("Invalid story format: missing required fields");
    }

    const enhancedScenes = parsedOutput.scenes.map((scene, index) => ({
      ...scene,
      id: scene.id || `scene_${index + 1}`,
      sceneNumber: scene.sceneNumber || index + 1,
      duration: scene.duration || 5,
      voice: scene.voice || "ElevenLabs Brian",
      audioPrompt: scene.audioPrompt || scene.audio || "Ambient background music",
      visualPrompt: scene.visualPrompt || scene.visual || ""
    }));

    return {
      ...parsedOutput,
      id: parsedOutput.id || `story_${Date.now()}`,
      template: parsedOutput.template || parsedOutput.prompt || "default",
      backgroundMusicPrompt: parsedOutput.backgroundMusicPrompt || "Gentle ambient background music with a moderate tempo, creating a neutral but engaging atmosphere",
      scenes: enhancedScenes
    };
  };

  // Create a function-calling chain
  const functionCallingChain = model.bind({
    functions: [storyFunctionSchema],
    function_call: { name: "create_story" }
  });

  // Compose the chain using RunnableSequence
  return RunnableSequence.from([
    {
      formattedPrompt: formatPrompt
    },
    async (data) => {
      const promptValue = await data.formattedPrompt;
      return promptValue;
    },
    functionCallingChain,
    outputParser,
    validateAndEnhanceOutput
  ]);
};

// Firebase Function to generate a story
export const generateStory = functions.https.onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError(
      "unauthenticated",
      "Must be signed in to generate stories"
    );
  }

  const { prompt } = request.data;
  if (!prompt || typeof prompt !== "string") {
    throw new HttpsError(
      "invalid-argument",
      "Prompt must be a non-empty string"
    );
  }

  try {
    const chain = createStoryChain();
    const result = await chain.invoke({
      prompt
    });

    // Add metadata to the result
    const storyWithMetadata = {
      ...result,
      createdAt: new Date().toISOString(),
      userId: auth.uid
    };

    return {
      success: true,
      result: storyWithMetadata
    };
  } catch (error) {
    console.error("Story generation error:", error);
    throw new HttpsError(
      "internal",
      error instanceof Error ? error.message : "Unknown error occurred"
    );
  }
});

// Rate limiter for ElevenLabs API
let lastElevenLabsRequest = 0;
const ELEVENLABS_REQUEST_DELAY = 3000; // 3 seconds between requests
const MAX_RETRIES = 3; // Maximum number of retries for concurrent request errors
const CONCURRENT_ERROR_DELAY = 5000; // 5 seconds wait when hitting concurrent limit

async function waitForElevenLabsRateLimit() {
  const now = Date.now();
  const timeSinceLastRequest = now - lastElevenLabsRequest;
  
  if (timeSinceLastRequest < ELEVENLABS_REQUEST_DELAY) {
    const waitTime = ELEVENLABS_REQUEST_DELAY - timeSinceLastRequest;
    console.log(`Waiting ${waitTime}ms before next ElevenLabs request`);
    await sleep(waitTime);
  }
  
  lastElevenLabsRequest = Date.now();
}

async function makeElevenLabsRequest(requestFn, retryCount = 0) {
  try {
    await waitForElevenLabsRateLimit();
    const response = await requestFn();
    
    if (!response.ok) {
      const errorText = await response.text();
      const errorJson = JSON.parse(errorText);
      
      // Check specifically for concurrent requests error
      if (errorJson?.detail?.status === "too_many_concurrent_requests" && retryCount < MAX_RETRIES) {
        console.log(`Hit concurrent request limit, retry ${retryCount + 1}/${MAX_RETRIES} after ${CONCURRENT_ERROR_DELAY}ms`);
        await sleep(CONCURRENT_ERROR_DELAY);
        return makeElevenLabsRequest(requestFn, retryCount + 1);
      }
      
      throw new Error(`ElevenLabs error: ${errorText}`);
    }
    
    return response;
  } catch (error) {
    if (error.message.includes("too_many_concurrent_requests") && retryCount < MAX_RETRIES) {
      console.log(`Hit concurrent request limit, retry ${retryCount + 1}/${MAX_RETRIES} after ${CONCURRENT_ERROR_DELAY}ms`);
      await sleep(CONCURRENT_ERROR_DELAY);
      return makeElevenLabsRequest(requestFn, retryCount + 1);
    }
    throw error;
  }
}

// Firebase Function to generate audio
export const generateAudio = functions.https.onCall(async (request) => {
  const functionStartTime = new Date().toISOString();
  console.log(`[${functionStartTime}] Starting audio generation request:`, {
    auth: request.auth?.uid,
    data: request.data
  });

  const auth = request.auth;
  if (!auth) {
    console.error("Authentication missing");
    throw new HttpsError(
      "unauthenticated",
      "Must be signed in to generate audio"
    );
  }

  const { storyId, sceneId, type, prompt } = request.data;
  console.log("Request parameters:", { storyId, sceneId, type, prompt });

  if (!storyId || !type || !prompt) {
    console.error("Missing required parameters:", { storyId, type, prompt });
    throw new HttpsError(
      "invalid-argument",
      "Must provide storyId, type, and prompt"
    );
  }

  try {
    let response;
    let initialApiResult;

    // Validate API request first before creating any documents
    switch (type) {
    case "backgroundMusic": {
      console.log("Starting background music generation with AIMLAPI");
        
      const requestBody = {
        model: "stable-audio",
        prompt,
        steps: 100,
        seconds_total: 45
      };
      console.log("AIMLAPI request body:", requestBody);

      response = await fetch("https://api.aimlapi.com/v2/generate/audio", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${process.env.AIMLAPI_API_KEY}`
        },
        body: JSON.stringify(requestBody)
      });

      if (!response.ok) {
        const errorText = await response.text();
        console.error("AIMLAPI initial request failed:", {
          status: response.status,
          statusText: response.statusText,
          error: errorText
        });
        throw new Error(`AIMLAPI error: ${errorText}`);
      }

      const musicData = await response.json();
      console.log("AIMLAPI initial response:", musicData);
      
      const generationId = musicData.id;
      if (!generationId) {
        console.error("No id in AIMLAPI response:", musicData);
        throw new Error("No id received from AIMLAPI");
      }

      initialApiResult = { generationId };
      break;
    }

    case "narration": {
      console.log("Starting narration generation with ElevenLabs");
      const BRIAN_VOICE_ID = "nPczCjzI2devNBz1zQrb";
      
      const requestBody = {
        text: prompt,
        model_id: "eleven_multilingual_v2",
        output_format: "mp3_44100_128",
        voice_settings: {
          stability: 0.5,
          similarity_boost: 0.75,
          style: 0.5,
          use_speaker_boost: true
        }
      };
      console.log("ElevenLabs request body:", requestBody);

      // Just validate the request, don't process response yet
      response = await makeElevenLabsRequest(async () => {
        return fetch(`https://api.elevenlabs.io/v1/text-to-speech/${BRIAN_VOICE_ID}`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "xi-api-key": process.env.ELEVENLABS_API_KEY
          },
          body: JSON.stringify(requestBody)
        });
      });

      if (!response.ok) {
        throw new Error(`ElevenLabs request failed with status ${response.status}`);
      }

      initialApiResult = { response };
      break;
    }

    case "soundEffect": {
      console.log("Starting sound effect generation with ElevenLabs");
      
      const requestBody = {
        text: prompt,
        duration_seconds: Math.min(22, Math.max(0.5, 5)),
        prompt_influence: 0.7
      };
      console.log("ElevenLabs sound effect request body:", requestBody);

      // Just validate the request, don't process response yet
      response = await makeElevenLabsRequest(async () => {
        return fetch("https://api.elevenlabs.io/v1/sound-generation", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "xi-api-key": process.env.ELEVENLABS_API_KEY
          },
          body: JSON.stringify(requestBody)
        });
      });

      if (!response.ok) {
        throw new Error(`ElevenLabs request failed with status ${response.status}`);
      }

      initialApiResult = { response };
      break;
    }

    default:
      throw new Error("Invalid audio type");
    }

    // If we get here, the initial API request was successful
    // Now create the audio document
    const audioId = `audio_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const audioRef = db.collection("users")
      .doc(auth.uid)
      .collection("stories")
      .doc(storyId)
      .collection("audio")
      .doc(audioId);

    const dateFormatter = new Intl.DateTimeFormat("en-US", {
      dateStyle: "short",
      timeStyle: "short"
    });
    const timestamp = dateFormatter.format(new Date());
    
    // Create initial audio document
    await audioRef.set({
      id: audioId,
      storyId,
      sceneId,
      userId: auth.uid,
      prompt,
      type,
      voice: type === "narration" ? "ElevenLabs Brian" : null,
      displayName: type === "backgroundMusic" 
        ? `Background Music (${timestamp})`
        : sceneId
          ? `${type === "narration" ? "Narration" : "Sound Effect"} - ${sceneId} (${timestamp})`
          : `${type === "narration" ? "Narration" : "Sound Effect"} (${timestamp})`,
      aimlapiUrl: null,
      mediaUrl: null,
      generationId: type === "backgroundMusic" ? initialApiResult.generationId : null,
      createdAt: FieldValue.serverTimestamp(),
      status: "generating"
    });

    // Return immediately with the audio document info
    let audioResult = {
      id: audioId,
      storyId,
      sceneId,
      userId: auth.uid,
      prompt,
      type,
      voice: type === "narration" ? "ElevenLabs Brian" : null,
      displayName: type === "backgroundMusic" 
        ? `Background Music (${timestamp})`
        : sceneId
          ? `${type === "narration" ? "Narration" : "Sound Effect"} - ${sceneId} (${timestamp})`
          : `${type === "narration" ? "Narration" : "Sound Effect"} (${timestamp})`,
      aimlapiUrl: null,
      mediaUrl: null,
      generationId: type === "backgroundMusic" ? initialApiResult.generationId : null,
      createdAt: new Date().toISOString(),
      status: "pending"
    };

    // Process the audio generation asynchronously
    (async () => {
      try {
        switch (type) {
        case "backgroundMusic": {
          // Poll for the result
          let attempts = 0;
          const maxAttempts = 12; // 1 minute with 5-second intervals
        
          console.log("Starting polling loop for id:", initialApiResult.generationId);
        
          while (attempts < maxAttempts) {
            attempts++; // Single increment at the start of the loop
            console.log(`Polling attempt ${attempts}/${maxAttempts}`);
          
            try {
              const pollResponse = await fetch(`https://api.aimlapi.com/v2/generate/audio?generation_id=${initialApiResult.generationId}`, {
                method: "GET",
                headers: {
                  "Accept": "application/json",
                  "Content-Type": "application/json",
                  "Authorization": `Bearer ${process.env.AIMLAPI_API_KEY}`
                }
              });
            
              if (!pollResponse || !pollResponse.ok) {
                const errorText = await pollResponse?.text() || "No response received";
                console.error("AIMLAPI polling request failed:", {
                  status: pollResponse?.status,
                  statusText: pollResponse?.statusText,
                  error: errorText,
                  attempt: attempts
                });
                throw new Error(`AIMLAPI polling error: ${errorText}`);
              }

              const pollData = await pollResponse.json();
              if (!pollData) {
                console.error("No data received from AIMLAPI poll");
                throw new Error("No data received from AIMLAPI poll");
              }

              console.log("Poll response:", {
                status: pollData.status,
                hasUrl: !!pollData.audio_file?.url,
                attempt: attempts
              });

              if (pollData.status === "completed" && pollData.audio_file?.url) {
                // Update the document with the AIMLAPI URL
                await audioRef.update({
                  aimlapiUrl: pollData.audio_file.url,
                  status: "pending"
                });
                
                try {
                  console.log("Converting pending audio with AIMLAPI URL:", {
                    audioId: audioId,
                    aimlapiUrl: pollData.audio_file.url
                  });

                  // Create temporary file paths
                  const inputPath = join(tmpdir(), `${audioId}_input.wav`);
                  const outputPath = join(tmpdir(), `${audioId}_output.mp3`);

                  // Download the file from AIMLAPI
                  const response = await fetch(pollData.audio_file.url);
                  if (!response.ok) {
                    throw new Error(`Failed to download audio: ${response.statusText}`);
                  }

                  // Save the downloaded file
                  const fileStream = createWriteStream(inputPath);
                  await new Promise((resolve, reject) => {
                    response.body.pipe(fileStream)
                      .on("finish", resolve)
                      .on("error", reject);
                  });

                  // Convert the file using ffmpeg
                  await new Promise((resolve, reject) => {
                    ffmpeg(inputPath)
                      .toFormat("mp3")
                      .audioBitrate("128k")
                      .audioChannels(2)
                      .audioFrequency(44100)
                      .on("end", resolve)
                      .on("error", reject)
                      .save(outputPath);
                  });

                  // Upload to Firebase Storage
                  const storage = getStorage();
                  const storagePath = `users/${auth.uid}/stories/${storyId}/audio/${audioId}.mp3`;
                  const bucket = storage.bucket();
                  
                  await bucket.upload(outputPath, {
                    destination: storagePath,
                    metadata: {
                      contentType: "audio/mp3"
                    }
                  });

                  // Make the file public and get its public URL
                  const file = bucket.file(storagePath);
                  await file.makePublic();
                  const url = `https://storage.googleapis.com/${bucket.name}/${storagePath}`;

                  // Update the audio document
                  await audioRef.update({
                    mediaUrl: url,
                    status: "completed",
                    updatedAt: FieldValue.serverTimestamp()
                  });

                  // Clean up temporary files
                  await Promise.all([
                    unlink(inputPath),
                    unlink(outputPath)
                  ]);

                  console.log("Audio conversion completed successfully:", { audioId, url });
                  audioResult = {
                    ...audioResult,
                    audioUrl: url,
                    aimlapiUrl: pollData.audio_file.url,
                    mediaUrl: url,
                    status: "completed"
                  };
                  break;
                } catch (error) {
                  console.error("Error converting audio:", error);
                  await audioRef.update({
                    status: "failed",
                    error: error.message,
                    updatedAt: FieldValue.serverTimestamp()
                  });
                }
              } else if (pollData.error) {
                console.error("AIMLAPI generation error in poll response:", pollData.error);
                throw new Error(`AIMLAPI generation error: ${pollData.error}`);
              }

              await sleep(5000); // Wait 5 seconds
            } catch (pollError) {
              console.error("Error in polling attempt:", pollError);
              await sleep(5000); // Wait 5 seconds before retrying
            }
          }

          if (!audioResult) {
            console.error("Background music generation timed out after", attempts, "attempts");
            throw new Error("Background music generation timed out");
          }
          break;
        }

        case "narration": {
          // We already have the response from the initial request
          const audioBuffer = await initialApiResult.response.arrayBuffer();
          console.log("Successfully received audio buffer for narration");
        
          // Upload directly to Firebase Storage
          const storage = getStorage();
          const storagePath = `users/${auth.uid}/stories/${storyId}/audio/${audioId}.mp3`;
          const file = storage.bucket().file(storagePath);
        
          await file.save(Buffer.from(audioBuffer));
          await file.makePublic();
          const url = `https://storage.googleapis.com/${storage.bucket().name}/${storagePath}`;
        
          // Update the document
          await audioRef.update({
            mediaUrl: url,
            status: "completed",
            updatedAt: FieldValue.serverTimestamp()
          });
        
          audioResult = {
            ...audioResult,
            audioUrl: url,
            mediaUrl: url,
            status: "completed"
          };
          break;
        }

        case "soundEffect": {
          // We already have the response from the initial request
          const sfxBuffer = await initialApiResult.response.arrayBuffer();
          console.log("Successfully received audio buffer for sound effect");
        
          // Upload directly to Firebase Storage
          const storage = getStorage();
          const storagePath = `users/${auth.uid}/stories/${storyId}/audio/${audioId}.mp3`;
          const file = storage.bucket().file(storagePath);
        
          await file.save(Buffer.from(sfxBuffer));
          await file.makePublic();
          const url = `https://storage.googleapis.com/${storage.bucket().name}/${storagePath}`;
        
          // Update the document
          await audioRef.update({
            mediaUrl: url,
            status: "completed",
            updatedAt: FieldValue.serverTimestamp()
          });
        
          audioResult = {
            ...audioResult,
            audioUrl: url,
            mediaUrl: url,
            status: "completed"
          };
          break;
        }

        default:
          console.error("Invalid audio type:", type);
          await audioRef.update({
            status: "failed",
            error: "Invalid audio type",
            updatedAt: FieldValue.serverTimestamp()
          });
        }
      } catch (error) {
        console.error("Async audio generation error:", error);
        await audioRef.update({
          status: "failed",
          error: error.message,
          updatedAt: FieldValue.serverTimestamp()
        });
      }
    })().catch(error => {
      console.error("Top-level async error:", error);
    });

    const functionEndTime = new Date().toISOString();
    console.log(`[${functionEndTime}] Audio generation request queued successfully:`, {
      type,
      audioId
    });

    return {
      success: true,
      result: audioResult
    };

  } catch (error) {
    const errorTime = new Date().toISOString();
    console.error(`[${errorTime}] Audio generation error:`, {
      error: error.message,
      stack: error.stack,
      type,
      storyId,
      sceneId
    });
    
    throw new HttpsError(
      "internal",
      error instanceof Error ? error.message : "Unknown error occurred"
    );
  }
});

// Test function to verify environment variables
export const testEnv = functions.https.onRequest((request, response) => {
  const envVars = {
    hasOpenAI: !!process.env.OPENAI_API_KEY,
    hasFirebaseProjectId: !!process.env.PROJECT_ID,
    hasLangSmith: !!process.env.LANGSMITH_API_KEY,
    nodeEnv: process.env.NODE_ENV
  };
  
  response.json({
    message: "Environment variables status",
    variables: envVars
  });
});

// Helper endpoint to get a test token (only available in emulator)
export const getTestToken = functions.https.onRequest(async (request, response) => {
  if (!process.env.FUNCTIONS_EMULATOR) {
    response.status(404).send("Not available in production");
    return;
  }

  try {
    const testUid = "test-user-1";
    const customToken = await getAuth().createCustomToken(testUid);
    response.json({ customToken });
  } catch (error) {
    console.error("Error creating test token:", error);
    response.status(500).json({ error: error.message });
  }
});

// Helper endpoint to get auth status (only available in emulator)
export const checkAuth = functions.https.onRequest(async (request, response) => {
  if (!process.env.FUNCTIONS_EMULATOR) {
    response.status(404).send("Not available in production");
    return;
  }

  const authHeader = request.headers.authorization;
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    response.status(401).json({ error: "No token provided" });
    return;
  }

  try {
    const idToken = authHeader.split("Bearer ")[1];
    const decodedToken = await getAuth().verifyIdToken(idToken);
    response.json({
      uid: decodedToken.uid,
      email: decodedToken.email,
      authenticated: true
    });
  } catch (error) {
    console.error("Auth error:", error);
    response.status(401).json({ error: error.message });
  }
});

// Add the new function
export const convertAudio = functions.https.onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError(
      "unauthenticated",
      "Must be signed in to convert audio"
    );
  }

  const { audioId, storyId, aimlapiUrl } = request.data;
  if (!audioId || !storyId || !aimlapiUrl) {
    throw new HttpsError(
      "invalid-argument",
      "Must provide audioId, storyId, and aimlapiUrl"
    );
  }

  try {
    // First verify that this audio belongs to the authenticated user
    const audioRef = db.collection("users")
      .doc(auth.uid)
      .collection("stories")
      .doc(storyId)
      .collection("audio")
      .doc(audioId);

    const audioDoc = await audioRef.get();
    if (!audioDoc.exists) {
      throw new HttpsError(
        "not-found",
        "Audio document not found"
      );
    }

    const audioData = audioDoc.data();
    if (audioData.userId !== auth.uid) {
      throw new HttpsError(
        "permission-denied",
        "You don't have permission to modify this audio"
      );
    }

    console.log("Starting audio conversion:", { audioId, storyId, aimlapiUrl });

    // Create temporary file paths
    const inputPath = join(tmpdir(), `${audioId}_input.wav`);
    const outputPath = join(tmpdir(), `${audioId}_output.mp3`);

    // Download the file from AIMLAPI
    const response = await fetch(aimlapiUrl);
    if (!response.ok) {
      throw new Error(`Failed to download audio: ${response.statusText}`);
    }

    // Save the downloaded file
    const fileStream = createWriteStream(inputPath);
    await new Promise((resolve, reject) => {
      response.body.pipe(fileStream)
        .on("finish", resolve)
        .on("error", reject);
    });

    // Convert the file using ffmpeg
    await new Promise((resolve, reject) => {
      ffmpeg(inputPath)
        .toFormat("mp3")
        .audioBitrate("128k")
        .audioChannels(2)
        .audioFrequency(44100)
        .on("end", resolve)
        .on("error", reject)
        .save(outputPath);
    });

    // Upload to Firebase Storage
    const storage = getStorage();
    const storagePath = `users/${auth.uid}/stories/${storyId}/audio/${audioId}.mp3`;
    const bucket = storage.bucket();
    
    await bucket.upload(outputPath, {
      destination: storagePath,
      metadata: {
        contentType: "audio/mp3"
      }
    });

    // Instead of getting a signed URL, make the file public and get its public URL
    const file = bucket.file(storagePath);
    await file.makePublic();
    const url = `https://storage.googleapis.com/${bucket.name}/${storagePath}`;

    // Update the audio document
    await audioRef.update({
      mediaUrl: url,
      status: "completed",
      updatedAt: FieldValue.serverTimestamp()
    });

    // Clean up temporary files
    await Promise.all([
      unlink(inputPath),
      unlink(outputPath)
    ]);

    console.log("Audio conversion completed successfully:", { audioId, url });

    return {
      success: true,
      result: { mediaUrl: url }
    };

  } catch (error) {
    console.error("Audio conversion error:", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError(
      "internal",
      error instanceof Error ? error.message : "Unknown error occurred"
    );
  }
});

// Add the recheck function
export const recheckAudio = functions.https.onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError(
      "unauthenticated",
      "Must be signed in to recheck audio"
    );
  }

  const { storyId } = request.data;
  if (!storyId) {
    throw new HttpsError(
      "invalid-argument",
      "Must provide storyId"
    );
  }

  try {
    // Get all audio documents for this story that are in pending or generating state
    const audioRef = db.collection("users")
      .doc(auth.uid)
      .collection("stories")
      .doc(storyId)
      .collection("audio");

    const pendingDocs = await audioRef
      .where("status", "in", ["pending", "generating"])
      .get();

    if (pendingDocs.empty) {
      return {
        success: true,
        result: {
          message: "No pending audio files found",
          checkedCount: 0,
          updatedCount: 0
        }
      };
    }

    let checkedCount = 0;
    let updatedCount = 0;

    // Process each pending document
    for (const doc of pendingDocs.docs) {
      const audioData = doc.data();
      checkedCount++;

      if (audioData.type === "backgroundMusic") {
        // Case 1: Has generationId but no aimlapiUrl - needs to check AIMLAPI status
        if (audioData.generationId && !audioData.aimlapiUrl) {
          try {
            const pollResponse = await fetch(`https://api.aimlapi.com/v2/generate/audio?generation_id=${audioData.generationId}`, {
              method: "GET",
              headers: {
                "Accept": "application/json",
                "Content-Type": "application/json",
                "Authorization": `Bearer ${process.env.AIMLAPI_API_KEY}`
              }
            });

            if (!pollResponse || !pollResponse.ok) {
              const errorText = await pollResponse?.text() || "No response received";
              console.error("AIMLAPI recheck failed:", {
                audioId: doc.id,
                status: pollResponse?.status,
                error: errorText
              });
              continue;
            }

            const pollData = await pollResponse.json();
            
            if (pollData.status === "completed" && pollData.audio_file?.url) {
              // Update the document with the AIMLAPI URL
              await doc.ref.update({
                aimlapiUrl: pollData.audio_file.url,
                status: "pending"
              });

              try {
                console.log("Converting pending audio with AIMLAPI URL:", {
                  audioId: doc.id,
                  aimlapiUrl: pollData.audio_file.url
                });

                // Create temporary file paths
                const inputPath = join(tmpdir(), `${doc.id}_input.wav`);
                const outputPath = join(tmpdir(), `${doc.id}_output.mp3`);

                // Download the file from AIMLAPI
                const response = await fetch(pollData.audio_file.url);
                if (!response.ok) {
                  throw new Error(`Failed to download audio: ${response.statusText}`);
                }

                // Save the downloaded file
                const fileStream = createWriteStream(inputPath);
                await new Promise((resolve, reject) => {
                  response.body.pipe(fileStream)
                    .on("finish", resolve)
                    .on("error", reject);
                });

                // Convert the file using ffmpeg
                await new Promise((resolve, reject) => {
                  ffmpeg(inputPath)
                    .toFormat("mp3")
                    .audioBitrate("128k")
                    .audioChannels(2)
                    .audioFrequency(44100)
                    .on("end", resolve)
                    .on("error", reject)
                    .save(outputPath);
                });

                // Upload to Firebase Storage
                const storage = getStorage();
                const storagePath = `users/${auth.uid}/stories/${storyId}/audio/${doc.id}.mp3`;
                const bucket = storage.bucket();
                
                await bucket.upload(outputPath, {
                  destination: storagePath,
                  metadata: {
                    contentType: "audio/mp3"
                  }
                });

                // Make the file public and get its public URL
                const file = bucket.file(storagePath);
                await file.makePublic();
                const url = `https://storage.googleapis.com/${bucket.name}/${storagePath}`;

                // Update the audio document
                await doc.ref.update({
                  mediaUrl: url,
                  status: "completed",
                  updatedAt: FieldValue.serverTimestamp()
                });

                // Clean up temporary files
                await Promise.all([
                  unlink(inputPath),
                  unlink(outputPath)
                ]);

                console.log("Audio conversion completed successfully:", { audioId: doc.id, url });
                updatedCount++;
              } catch (error) {
                console.error("Error converting audio:", error);
                await doc.ref.update({
                  status: "failed",
                  error: error.message,
                  updatedAt: FieldValue.serverTimestamp()
                });
                updatedCount++;
              }
            } else if (pollData.error || pollData.status === "failed") {
              await doc.ref.update({
                status: "failed",
                error: pollData.error || "Generation failed",
                updatedAt: FieldValue.serverTimestamp()
              });
              updatedCount++;
            }
          } catch (error) {
            console.error("Error rechecking AIMLAPI status:", error);
          }
        }
        // Case 2: Has aimlapiUrl but no mediaUrl - needs conversion
        else if (audioData.aimlapiUrl && !audioData.mediaUrl && audioData.status === "pending") {
          try {
            console.log("Converting pending audio with AIMLAPI URL:", {
              audioId: doc.id,
              aimlapiUrl: audioData.aimlapiUrl
            });

            // Create temporary file paths
            const inputPath = join(tmpdir(), `${doc.id}_input.wav`);
            const outputPath = join(tmpdir(), `${doc.id}_output.mp3`);

            // Download the file from AIMLAPI
            const response = await fetch(audioData.aimlapiUrl);
            if (!response.ok) {
              throw new Error(`Failed to download audio: ${response.statusText}`);
            }

            // Save the downloaded file
            const fileStream = createWriteStream(inputPath);
            await new Promise((resolve, reject) => {
              response.body.pipe(fileStream)
                .on("finish", resolve)
                .on("error", reject);
            });

            // Convert the file using ffmpeg
            await new Promise((resolve, reject) => {
              ffmpeg(inputPath)
                .toFormat("mp3")
                .audioBitrate("128k")
                .audioChannels(2)
                .audioFrequency(44100)
                .on("end", resolve)
                .on("error", reject)
                .save(outputPath);
            });

            // Upload to Firebase Storage
            const storage = getStorage();
            const storagePath = `users/${auth.uid}/stories/${storyId}/audio/${doc.id}.mp3`;
            const bucket = storage.bucket();
            
            await bucket.upload(outputPath, {
              destination: storagePath,
              metadata: {
                contentType: "audio/mp3"
              }
            });

            // Make the file public and get its public URL
            const file = bucket.file(storagePath);
            await file.makePublic();
            const url = `https://storage.googleapis.com/${bucket.name}/${storagePath}`;

            // Update the audio document
            await doc.ref.update({
              mediaUrl: url,
              status: "completed",
              updatedAt: FieldValue.serverTimestamp()
            });

            // Clean up temporary files
            await Promise.all([
              unlink(inputPath),
              unlink(outputPath)
            ]);

            console.log("Audio conversion completed successfully:", { audioId: doc.id, url });
            updatedCount++;
          } catch (error) {
            console.error("Error converting audio:", error);
            await doc.ref.update({
              status: "failed",
              error: error.message,
              updatedAt: FieldValue.serverTimestamp()
            });
            updatedCount++;
          }
        }
        // Case 3: Has mediaUrl but status is still pending - just needs status update
        else if (audioData.mediaUrl && audioData.status === "pending") {
          try {
            console.log("Found completed audio still marked as pending:", {
              audioId: doc.id,
              mediaUrl: audioData.mediaUrl
            });

            // Update the audio document to completed
            await doc.ref.update({
              status: "completed",
              updatedAt: FieldValue.serverTimestamp()
            });

            console.log("Updated audio status to completed:", { audioId: doc.id });
            updatedCount++;
          } catch (error) {
            console.error("Error updating audio status:", error);
          }
        }
      }
    }

    return {
      success: true,
      result: {
        message: `Checked ${checkedCount} audio files, updated ${updatedCount}`,
        checkedCount,
        updatedCount
      }
    };

  } catch (error) {
    console.error("Audio recheck error:", error);
    throw new HttpsError(
      "internal",
      error instanceof Error ? error.message : "Unknown error occurred"
    );
  }
}); 