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

// Initialize Firebase Admin with emulator configuration
const app = initializeApp({
  projectId: process.env.PROJECT_ID || "demo-project",
});

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