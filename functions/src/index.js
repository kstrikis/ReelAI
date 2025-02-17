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
import * as fs from "fs";

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
        // First check if we already have a mediaUrl
        if (audioData.mediaUrl) {
          // If we have a mediaUrl, just mark as completed and continue to next file
          await doc.ref.update({
            status: "completed"
          });
          updatedCount++;
          continue;
        }

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

// Firebase Function to generate video clips
export const generateVideo = functions.https.onCall(async (request) => {
  const functionStartTime = new Date().toISOString();
  console.log(`[${functionStartTime}] Starting video generation request:`, {
    auth: request.auth?.uid,
    data: request.data,
    hasApiKey: !!process.env.AIMLAPI_API_KEY,
    environment: process.env.NODE_ENV
  });

  const auth = request.auth;
  if (!auth) {
    console.error("Authentication missing");
    throw new HttpsError(
      "unauthenticated",
      "Must be signed in to generate video"
    );
  }

  const { storyId, sceneId, prompt, duration } = request.data;
  console.log("Request parameters validation:", { 
    hasStoryId: !!storyId,
    hasSceneId: !!sceneId,
    promptLength: prompt?.length,
    duration: duration,
    isValidDuration: duration >= 1 && duration <= 10
  });

  if (!storyId || !sceneId || !prompt) {
    console.error("Missing required parameters:", { storyId, sceneId, prompt });
    throw new HttpsError(
      "invalid-argument",
      "Must provide storyId, sceneId, and prompt"
    );
  }

  try {
    // Create initial video document
    const videoId = `video_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const videoRef = db.collection("users")
      .doc(auth.uid)
      .collection("stories")
      .doc(storyId)
      .collection("videos")
      .doc(videoId);

    const dateFormatter = new Intl.DateTimeFormat("en-US", {
      dateStyle: "short",
      timeStyle: "short"
    });
    const timestamp = dateFormatter.format(new Date());

    // Initial video document
    await videoRef.set({
      id: videoId,
      storyId,
      sceneId,
      userId: auth.uid,
      prompt,
      displayName: `Scene ${sceneId} (${timestamp})`,
      aimlapiUrl: null,
      mediaUrl: null,
      generationId: null,
      createdAt: FieldValue.serverTimestamp(),
      status: "generating"
    });

    // Make the initial API request
    console.log("Starting video generation with AIMLAPI Kling");
    
    const requestBody = {
      model: "kling-video/v1.6/standard/text-to-video",
      prompt,
      duration: duration <= 5 ? "5" : "10", // Round to duration
      ratio: "9:16"
    };
    console.log("AIMLAPI request body:", requestBody);

    const response = await fetch("https://api.aimlapi.com/v2/generate/video/kling/generation", {
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

    const videoData = await response.json();
    console.log("AIMLAPI initial response:", videoData);
    
    const generationId = videoData.id;
    if (!generationId) {
      console.error("No id in AIMLAPI response:", videoData);
      throw new Error("No id received from AIMLAPI");
    }

    // Update document with generation ID
    await videoRef.update({
      generationId
    });

    // Start polling in the background
    (async () => {
      try {
        let attempts = 0;
        const maxAttempts = 60; // 10 minutes with 10-second intervals
        
        console.log("Starting polling loop for id:", generationId);
        
        while (attempts < maxAttempts) {
          attempts++; // Single increment at the start of the loop
          console.log(`Polling attempt ${attempts}/${maxAttempts}`);
        
          try {
            const pollResponse = await fetch(`https://api.aimlapi.com/v2/generate/video/kling/generation?generation_id=${generationId}`, {
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
              
              // Mark video as failed if we get a 404 response
              if (pollResponse?.status === 404) {
                await videoRef.update({
                  status: "failed",
                  error: "Video generation not found: The generation may have expired or been deleted",
                  updatedAt: FieldValue.serverTimestamp()
                });
                console.log("Marked video as failed due to 404 response:", videoId);
              }
              return;
            }

            const pollData = await pollResponse.json();
            console.log("Full poll response for video generation:", {
              generationId,
              pollData,
              status: pollData.status,
              hasVideoUrl: !!pollData.video?.url,
              videoMetadata: pollData.video || null,
              error: pollData.error || null,
              timestamp: new Date().toISOString()
            });

            if (pollData.status === "completed") {
              console.log("Generation completed, getting video details...");
              
              // Get the video URL from the poll response
              if (pollData.video?.url) {
                const videoUrl = pollData.video.url;
                console.log("Got video URL:", videoUrl);

                // First update document with AIMLAPI URL and change status to pending
                await videoRef.update({
                  aimlapiUrl: videoUrl,
                  status: "pending",
                  updatedAt: FieldValue.serverTimestamp()
                });
                console.log("Updated document with AIMLAPI URL, status now pending");

                try {
                  // Download the video file
                  console.log("Attempting to retrieve video from AIMLAPI URL:", videoUrl);
                  const videoResponse = await fetch(videoUrl);
                  if (!videoResponse.ok) {
                    console.error("Failed to retrieve video from AIMLAPI:", {
                      status: videoResponse.status,
                      statusText: videoResponse.statusText
                    });
                    throw new Error(`Failed to download video: ${videoResponse.statusText}`);
                  }
                  console.log("Successfully retrieved video from AIMLAPI");

                  // Upload to Firebase Storage
                  console.log("Starting upload to Firebase Storage");
                  const storage = getStorage();
                  const storagePath = `users/${auth.uid}/stories/${storyId}/videos/${videoId}.mp4`;
                  console.log("Target storage path:", storagePath);
                  
                  const bucket = storage.bucket();
                  const file = bucket.file(storagePath);

                  // Create write stream and pipe the video data
                  console.log("Creating write stream for Firebase Storage upload");
                  const writeStream = file.createWriteStream({
                    metadata: {
                      contentType: "video/mp4"
                    }
                  });

                  await new Promise((resolve, reject) => {
                    videoResponse.body.pipe(writeStream)
                      .on("finish", () => {
                        console.log("Video data successfully written to Firebase Storage");
                        resolve();
                      })
                      .on("error", (error) => {
                        console.error("Error writing video data to Firebase Storage:", error);
                        reject(error);
                      });
                  });

                  // Make the file public
                  console.log("Making Firebase Storage file public");
                  await file.makePublic();
                  const firebaseUrl = `https://storage.googleapis.com/${bucket.name}/${storagePath}`;
                  console.log("Generated public Firebase Storage URL:", firebaseUrl);

                  // Update the document with both URLs
                  console.log("Updating Firestore document with Firebase Storage URL and marking as completed");
                  await videoRef.update({
                    mediaUrl: firebaseUrl,
                    status: "completed",
                    updatedAt: FieldValue.serverTimestamp()
                  });
                  
                  console.log("Video generation and storage completed successfully:", {
                    videoId,
                    aimlapiUrl: videoUrl,
                    mediaUrl: firebaseUrl,
                    status: "completed"
                  });
                } catch (storageError) {
                  console.error("Error saving video to storage:", storageError);
                  await videoRef.update({
                    status: "failed",
                    error: `Storage error: ${storageError.message}`,
                    updatedAt: FieldValue.serverTimestamp()
                  });
                }
              } else {
                throw new Error("No video URL in response");
              }
            } else if (pollData.error || pollData.status === "failed") {
              console.error("AIMLAPI generation failed:", pollData.error);
              await videoRef.update({
                status: "failed",
                error: pollData.error || "Generation failed",
                updatedAt: FieldValue.serverTimestamp()
              });
              break;
            }

            await sleep(10000); // Wait 510seconds between polls
          } catch (pollError) {
            console.error("Error in polling attempt:", pollError);
            await sleep(10000); // Wait 10 seconds before retrying
          }
        }

        if (attempts >= maxAttempts) {
          console.error("Video generation timed out after", attempts, "attempts");
          await videoRef.update({
            status: "failed",
            error: "Generation timed out",
            updatedAt: FieldValue.serverTimestamp()
          });
        }
      } catch (error) {
        console.error("Async video generation error:", error);
        await videoRef.update({
          status: "failed",
          error: error.message,
          updatedAt: FieldValue.serverTimestamp()
        });
      }
    })().catch(error => {
      console.error("Top-level async error:", error);
    });

    // Return immediately with the video document info
    return {
      success: true,
      result: {
        id: videoId,
        storyId,
        sceneId,
        userId: auth.uid,
        prompt,
        displayName: `Scene ${sceneId} (${timestamp})`,
        aimlapiUrl: null,
        mediaUrl: null,
        generationId,
        createdAt: new Date().toISOString(),
        status: "pending"
      }
    };

  } catch (error) {
    const errorTime = new Date().toISOString();
    console.error(`[${errorTime}] Video generation error:`, {
      error: error.message,
      stack: error.stack,
      storyId,
      sceneId
    });
    
    throw new HttpsError(
      "internal",
      error instanceof Error ? error.message : "Unknown error occurred"
    );
  }
});

// Add the recheck video function
export const recheckVideo = functions.https.onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError(
      "unauthenticated",
      "Must be signed in to recheck video"
    );
  }

  const { storyId, videoId } = request.data;
  if (!storyId || !videoId) {
    throw new HttpsError(
      "invalid-argument",
      "Must provide storyId and videoId"
    );
  }

  try {
    // Get the video document
    const videoRef = db.collection("users")
      .doc(auth.uid)
      .collection("stories")
      .doc(storyId)
      .collection("videos")
      .doc(videoId);

    const videoDoc = await videoRef.get();
    if (!videoDoc.exists) {
      throw new HttpsError(
        "not-found",
        "Video document not found"
      );
    }

    const videoData = videoDoc.data();
    if (videoData.userId !== auth.uid) {
      throw new HttpsError(
        "permission-denied",
        "You don't have permission to modify this video"
      );
    }

    // Case 1: Already has mediaUrl - just needs status update
    if (videoData.mediaUrl) {
      console.log("Found video with mediaUrl but not marked completed:", {
        videoId,
        mediaUrl: videoData.mediaUrl
      });

      // Update the document to completed
      await videoRef.update({
        status: "completed",
        updatedAt: FieldValue.serverTimestamp()
      });
      
      console.log("Updated video status to completed:", { videoId });
      return {
        success: true,
        result: {
          message: "Video marked as completed"
        }
      };
    }

    // Case 2: Has generationId but no aimlapiUrl - needs to check AIMLAPI status
    if (videoData.generationId && !videoData.aimlapiUrl) {
      try {
        const pollResponse = await fetch(`https://api.aimlapi.com/v2/generate/video/kling/generation?generation_id=${videoData.generationId}`, {
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
            videoId,
            status: pollResponse?.status,
            error: errorText
          });
          
          // Mark video as failed if we get a 404 response
          if (pollResponse?.status === 404) {
            await videoRef.update({
              status: "failed",
              error: "Video generation not found: The generation may have expired or been deleted",
              updatedAt: FieldValue.serverTimestamp()
            });
            console.log("Marked video as failed due to 404 response:", videoId);
          }
          return;
        }

        const pollData = await pollResponse.json();
        console.log("Full poll response for video recheck:", {
          videoId,
          pollData,
          status: pollData.status,
          hasVideoUrl: !!pollData.video?.url,
          videoMetadata: pollData.video || null,
          error: pollData.error || null,
          timestamp: new Date().toISOString()
        });
        
        if (pollData.status === "completed" && pollData.video?.url) {
          const videoUrl = pollData.video.url;
          console.log("Got video URL:", videoUrl);

          try {
            // Download the video file
            const videoResponse = await fetch(videoUrl);
            if (!videoResponse.ok) {
              throw new Error(`Failed to download video: ${videoResponse.statusText}`);
            }

            // Upload to Firebase Storage
            const storage = getStorage();
            const storagePath = `users/${auth.uid}/stories/${storyId}/videos/${videoId}.mp4`;
            const bucket = storage.bucket();
            const file = bucket.file(storagePath);

            // Create write stream and pipe the video data
            const writeStream = file.createWriteStream({
              metadata: {
                contentType: "video/mp4"
              }
            });

            await new Promise((resolve, reject) => {
              videoResponse.body.pipe(writeStream)
                .on("finish", resolve)
                .on("error", reject);
            });

            // Make the file public
            await file.makePublic();
            const firebaseUrl = `https://storage.googleapis.com/${bucket.name}/${storagePath}`;

            // Update the document with both URLs
            await videoRef.update({
              aimlapiUrl: videoUrl,
              mediaUrl: firebaseUrl,
              status: "completed",
              updatedAt: FieldValue.serverTimestamp()
            });
            
            console.log("Video recheck completed successfully:", {
              videoId,
              aimlapiUrl: videoUrl,
              mediaUrl: firebaseUrl
            });
          } catch (storageError) {
            console.error("Error saving video to storage:", storageError);
            await videoRef.update({
              status: "failed",
              error: `Storage error: ${storageError.message}`,
              updatedAt: FieldValue.serverTimestamp()
            });
          }
        } else if (pollData.error || pollData.status === "failed") {
          console.error("AIMLAPI generation failed:", pollData.error);
          await videoRef.update({
            status: "failed",
            error: pollData.error || "Generation failed",
            updatedAt: FieldValue.serverTimestamp()
          });
        }
      } catch (error) {
        console.error("Error rechecking AIMLAPI status:", error);
      }
    }
    // Case 3: Has aimlapiUrl but no mediaUrl - needs to be uploaded to Firebase
    else if (videoData.aimlapiUrl && !videoData.mediaUrl) {
      try {
        // Download the video file
        const videoResponse = await fetch(videoData.aimlapiUrl);
        if (!videoResponse.ok) {
          throw new Error(`Failed to download video: ${videoResponse.statusText}`);
        }

        // Upload to Firebase Storage
        const storage = getStorage();
        const storagePath = `users/${auth.uid}/stories/${storyId}/videos/${videoId}.mp4`;
        const bucket = storage.bucket();
        const file = bucket.file(storagePath);

        // Create write stream and pipe the video data
        const writeStream = file.createWriteStream({
          metadata: {
            contentType: "video/mp4"
          }
        });

        await new Promise((resolve, reject) => {
          videoResponse.body.pipe(writeStream)
            .on("finish", resolve)
            .on("error", reject);
        });

        // Make the file public
        await file.makePublic();
        const firebaseUrl = `https://storage.googleapis.com/${bucket.name}/${storagePath}`;

        // Update the document
        await videoRef.update({
          mediaUrl: firebaseUrl,
          status: "completed",
          updatedAt: FieldValue.serverTimestamp()
        });
        
        console.log("Video upload completed successfully:", {
          videoId,
          mediaUrl: firebaseUrl
        });
      } catch (error) {
        console.error("Error uploading video to Firebase:", error);
        await videoRef.update({
          status: "failed",
          error: error.message,
          updatedAt: FieldValue.serverTimestamp()
        });
      }
    }

    return {
      success: true,
      result: {
        message: "Video recheck completed"
      }
    };

  } catch (error) {
    console.error("Video recheck error:", error);
    throw new HttpsError(
      "internal",
      error instanceof Error ? error.message : "Unknown error occurred"
    );
  }
});

// Add the assembleVideo function
export const assembleVideo = functions.https.onCall({
  memory: "1GiB",
  timeoutSeconds: 540,
  region: "us-central1"
}, async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError(
      "unauthenticated",
      "Must be signed in to assemble videos"
    );
  }

  const { storyId, clips } = request.data;
  if (!storyId || !clips || !Array.isArray(clips)) {
    throw new HttpsError(
      "invalid-argument",
      "Must provide storyId and clips array"
    );
  }

  try {
    // Get the story document
    const storyRef = db.collection("users")
      .doc(auth.uid)
      .collection("stories")
      .doc(storyId);

    const storyDoc = await storyRef.get();
    if (!storyDoc.exists) {
      throw new HttpsError(
        "not-found",
        "Story document not found"
      );
    }

    const story = storyDoc.data();
    if (story.userId !== auth.uid) {
      throw new HttpsError(
        "permission-denied",
        "You don't have permission to modify this story"
      );
    }

    // Create a new assembly document
    const assemblyId = `assembly_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const assemblyRef = storyRef.collection("assemblies").doc(assemblyId);

    const dateFormatter = new Intl.DateTimeFormat("en-US", {
      dateStyle: "short",
      timeStyle: "short"
    });
    const timestamp = dateFormatter.format(new Date());

    // Initial assembly document
    await assemblyRef.set({
      id: assemblyId,
      storyId,
      userId: auth.uid,
      displayName: `Assembly (${timestamp})`,
      mediaUrl: null,
      createdAt: FieldValue.serverTimestamp(),
      status: "assembling"
    });

    // Create temporary directory for processing
    const tempDir = join(tmpdir(), assemblyId);
    await fs.promises.mkdir(tempDir, { recursive: true });

    try {
      // Download all videos
      const videoFiles = [];
      let totalDuration = 0;
      for (const clip of clips) {
        const { sceneId, videoUrl, duration } = clip;
        if (!videoUrl) continue;

        const videoPath = join(tempDir, `${sceneId}.mp4`);
        const videoResponse = await fetch(videoUrl);
        if (!videoResponse.ok) {
          throw new Error(`Failed to download video: ${videoResponse.statusText}`);
        }

        const videoStream = createWriteStream(videoPath);
        await new Promise((resolve, reject) => {
          videoResponse.body.pipe(videoStream)
            .on("finish", resolve)
            .on("error", reject);
        });

        // Get actual video duration using ffprobe
        const actualDuration = await new Promise((resolve) => {
          ffmpeg.ffprobe(videoPath, (err, metadata) => {
            if (err) resolve(duration || 10); // Fallback to provided duration or 10 seconds
            resolve(metadata.format.duration);
          });
        });

        videoFiles.push({
          path: videoPath,
          sceneId,
          startTime: totalDuration,
          duration: actualDuration
        });
        totalDuration += actualDuration;
      }

      // Sort videos by scene number
      videoFiles.sort((a, b) => {
        const aNum = parseInt(a.sceneId.replace("scene", ""));
        const bNum = parseInt(b.sceneId.replace("scene", ""));
        return aNum - bNum;
      });

      // Create a list file for ffmpeg
      const listPath = join(tempDir, "list.txt");
      const listContent = videoFiles.map(f => `file '${f.path}'`).join("\n");
      await fs.promises.writeFile(listPath, listContent);

      // First concatenate all videos
      const concatenatedPath = join(tempDir, "concatenated.mp4");
      await new Promise((resolve, reject) => {
        ffmpeg()
          .input(listPath)
          .inputOptions(["-f", "concat", "-safe", "0"])
          .output(concatenatedPath)
          .on("end", resolve)
          .on("error", reject)
          .run();
      });

      // Create a timing map for each scene
      const sceneTimings = {};
      for (const file of videoFiles) {
        sceneTimings[file.sceneId] = {
          startTime: file.startTime,
          duration: file.duration
        };
      }

      // Prepare audio files with their timing information
      let filterComplex = [];
      let inputCount = 1; // Start at 1 because video is input 0
      let audioMixInputs = [];
      let audioInputs = []; // Track our inputs in order

      console.log("Starting audio assembly with clips:", clips.map(c => ({
        sceneId: c.sceneId,
        hasBGM: !!request.data.backgroundMusicUrl,
        hasNarration: !!c.audioUrl,
        hasSFX: !!c.soundEffectUrl,
        startTime: sceneTimings[c.sceneId]?.startTime,
        duration: sceneTimings[c.sceneId]?.duration
      })));

      // Add background music if provided
      if (request.data.backgroundMusicUrl) {
        const bgmPath = join(tempDir, "bgm.mp3");
        const bgmResponse = await fetch(request.data.backgroundMusicUrl);
        if (!bgmResponse.ok) {
          throw new Error(`Failed to download BGM: ${bgmResponse.statusText}`);
        }
        const bgmStream = createWriteStream(bgmPath);
        await new Promise((resolve, reject) => {
          bgmResponse.body.pipe(bgmStream)
            .on("finish", resolve)
            .on("error", reject);
        });

        // Add BGM with volume adjustment and duration trim
        filterComplex.push(`[${inputCount}:a]volume=0.3,atrim=0:${totalDuration}[bgm]`);
        audioMixInputs.push("[bgm]");
        audioInputs.push({ type: "bgm", path: bgmPath });
        inputCount++;
      }

      // Process narrations and sound effects
      for (const clip of clips) {
        const timing = sceneTimings[clip.sceneId];
        if (!timing) continue;

        const { audioUrl, soundEffectUrl } = clip;
        const { startTime, duration } = timing;
        
        // Add narration
        if (audioUrl) {
          const narrationPath = join(tempDir, `narration_${clip.sceneId}.mp3`);
          const narrationResponse = await fetch(audioUrl);
          if (!narrationResponse.ok) {
            throw new Error(`Failed to download narration: ${narrationResponse.statusText}`);
          }
          const narrationStream = createWriteStream(narrationPath);
          await new Promise((resolve, reject) => {
            narrationResponse.body.pipe(narrationStream)
              .on("finish", resolve)
              .on("error", reject);
          });

          // Add narration with delay, volume, and duration trim
          const delayMs = Math.round(startTime * 1000);
          filterComplex.push(`[${inputCount}:a]adelay=${delayMs}|${delayMs},volume=1,atrim=0:${totalDuration}[narr${clip.sceneId}]`);
          audioMixInputs.push(`[narr${clip.sceneId}]`);
          audioInputs.push({ type: "narration", path: narrationPath });
          inputCount++;
        }

        // Add sound effect
        if (soundEffectUrl) {
          const sfxPath = join(tempDir, `sfx_${clip.sceneId}.mp3`);
          const sfxResponse = await fetch(soundEffectUrl);
          if (!sfxResponse.ok) {
            throw new Error(`Failed to download SFX: ${sfxResponse.statusText}`);
          }
          const sfxStream = createWriteStream(sfxPath);
          await new Promise((resolve, reject) => {
            sfxResponse.body.pipe(sfxStream)
              .on("finish", resolve)
              .on("error", reject);
          });

          // Get SFX duration to calculate start time
          const sfxDuration = await new Promise((resolve) => {
            ffmpeg.ffprobe(sfxPath, (err, metadata) => {
              if (err) resolve(5); // Default to 5 seconds if can't determine
              resolve(metadata.format.duration);
            });
          });

          // Calculate start time to align end with clip end
          const sfxStartTime = Math.max(0, startTime + (duration - sfxDuration));
          const delayMs = Math.round(sfxStartTime * 1000);
          filterComplex.push(`[${inputCount}:a]adelay=${delayMs}|${delayMs},volume=0.7,atrim=0:${totalDuration}[sfx${clip.sceneId}]`);
          audioMixInputs.push(`[sfx${clip.sceneId}]`);
          audioInputs.push({ type: "sfx", path: sfxPath });
          inputCount++;
        }
      }

      // Final mix of all audio streams
      if (audioMixInputs.length > 0) {
        // Mix all audio streams with normalized volumes
        filterComplex.push(`${audioMixInputs.join("")}amix=inputs=${audioMixInputs.length}:duration=longest:normalize=0[aout]`);
      }

      console.log("Audio assembly configuration:", {
        totalInputs: inputCount,
        filterComplex,
        audioMixInputs,
        audioInputPaths: audioInputs.map(a => ({ type: a.type, path: a.path }))
      });

      // Combine video with mixed audio
      const outputPath = join(tempDir, "output.mp4");
      const ffmpegCommand = ffmpeg(concatenatedPath);

      // Add all audio inputs in the exact order we used in filter complex
      for (const audioInput of audioInputs) {
        ffmpegCommand.input(audioInput.path);
      }

      // Apply filter complex and output
      if (audioMixInputs.length > 0) {
        await new Promise((resolve, reject) => {
          ffmpegCommand
            .complexFilter(filterComplex)
            .outputOptions([
              "-map", "0:v", // Map video from first input
              "-map", "[aout]", // Map mixed audio
              "-c:v", "copy", // Copy video codec
              "-c:a", "aac", // Use AAC for audio
              "-b:a", "192k" // Set audio bitrate
            ])
            .output(outputPath)
            .on("start", cmdline => {
              console.log("FFmpeg command:", cmdline);
            })
            .on("end", resolve)
            .on("error", (err) => {
              console.error("FFmpeg error:", err.message);
              reject(err);
            })
            .run();
        });
      } else {
        // If no audio, just copy the video
        await new Promise((resolve, reject) => {
          ffmpegCommand
            .output(outputPath)
            .on("end", resolve)
            .on("error", (err) => {
              console.error("FFmpeg error:", err.message);
              reject(err);
            })
            .run();
        });
      }

      // Upload to Firebase Storage
      const storage = getStorage();
      const storagePath = `users/${auth.uid}/stories/${storyId}/assemblies/${assemblyId}.mp4`;
      const bucket = storage.bucket();
      const file = bucket.file(storagePath);

      await bucket.upload(outputPath, {
        destination: storagePath,
        metadata: {
          contentType: "video/mp4"
        }
      });

      // Make the file public
      await file.makePublic();
      const url = `https://storage.googleapis.com/${bucket.name}/${storagePath}`;

      // Update the assembly document
      await assemblyRef.update({
        mediaUrl: url,
        status: "completed",
        updatedAt: FieldValue.serverTimestamp()
      });

      // Clean up temporary files
      await fs.promises.rm(tempDir, { recursive: true, force: true });

      return {
        success: true,
        result: {
          id: assemblyId,
          mediaUrl: url,
          status: "completed"
        }
      };

    } catch (error) {
      // Clean up temporary files on error
      await fs.promises.rm(tempDir, { recursive: true, force: true });
      throw error;
    }

  } catch (error) {
    console.error("Video assembly error:", error);
    throw new HttpsError(
      "internal",
      error instanceof Error ? error.message : "Unknown error occurred"
    );
  }
}); 