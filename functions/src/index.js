// Environment variables are automatically loaded by Firebase Functions
import * as functions from "firebase-functions/v2";
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { ChatOpenAI } from "@langchain/openai";
import { ChatPromptTemplate, SystemMessagePromptTemplate, HumanMessagePromptTemplate } from "@langchain/core/prompts";
import { SystemMessage, HumanMessage, AIMessage } from "@langchain/core/messages";
import { JsonOutputFunctionsParser } from "langchain/output_parsers";
import { RunnableSequence } from "@langchain/core/runnables";
import { z } from "zod";
import { HttpsError } from "firebase-functions/v2/https";

// Initialize Firebase Admin with emulator configuration
const app = initializeApp({
  projectId: process.env.FIREBASE_PROJECT_ID || 'demo-project',
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
  scenes: z.array(SceneSchema),
  createdAt: z.string(), // ISO date string
  userId: z.string(),
});

// Story generation prompt template
const storyPromptTemplate = ChatPromptTemplate.fromMessages([
  HumanMessagePromptTemplate.fromTemplate(
    "You are a creative storyteller that creates engaging, multi-scene stories.\n\n" +
    "Create a story based on this prompt: {prompt}\n\n" +
    "The story should have:\n" +
    "1. A compelling title\n" +
    "2. 3-5 scenes, each with:\n" +
    "   - Narration text\n" +
    "   - A voice style suggestion (e.g., \"ElevenLabs Adam\", \"TikTok Voice 4\")\n" +
    "   - A visual prompt for image/video generation\n" +
    "   - An audio prompt for background sounds\n" +
    "   - An estimated duration in seconds (between 3-10 seconds)\n\n" +
    "Remember to make the story engaging and suitable for video generation."
  )
]);

// Simple test prompt for debugging
const testPromptTemplate = ChatPromptTemplate.fromTemplate("Tell me a one-sentence story about {topic}");

// Test function to verify prompt template functionality
export const testPrompt = functions.https.onRequest(async (request, response) => {
  if (!process.env.FUNCTIONS_EMULATOR) {
    response.status(404).send('Not available in production');
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
              description: "Prompt for background sounds or music"
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
    required: ["title", "scenes"]
  }
};

// Create the story generation chain
const createStoryChain = () => {
  const model = new ChatOpenAI({
    modelName: "gpt-4-1106-preview",
    temperature: 0.8
  });

  const systemTemplate = SystemMessagePromptTemplate.fromTemplate(
    "You are a creative storyteller specializing in engaging, multi-scene stories optimized for video generation. " +
    "Your stories should be visually compelling, emotionally resonant, and suitable for modern social media platforms. " +
    "Each scene should flow naturally into the next, creating a cohesive narrative that captures and maintains viewer attention."
  );

  const formatPrompt = ChatPromptTemplate.fromMessages([
    systemTemplate,
    HumanMessagePromptTemplate.fromTemplate(
      "Create an engaging story based on this prompt: {prompt}\n\n" +
      "Requirements:\n" +
      "1. Title: Create a compelling, memorable title\n" +
      "2. Scenes (3-5):\n" +
      "   - Narration: Clear, engaging text that drives the story forward\n" +
      "   - Voice: Suggest a specific voice style (e.g., \"ElevenLabs Adam\", \"TikTok Voice 4\")\n" +
      "   - Visual: Detailed prompt for image/video generation (style, mood, action, etc.)\n" +
      "   - Audio: Background sound suggestions that enhance the atmosphere\n" +
      "   - Duration: 3-10 seconds per scene\n\n" +
      "Make it engaging, memorable, and optimized for social media sharing."
    )
  ]);

  const outputParser = new JsonOutputFunctionsParser();

  // Define transformation steps
  const logInput = (input) => {
    console.log("Story generation input:", input);
    return input;
  };

  const logPrompt = (promptValue) => {
    console.log("Formatted prompt:", promptValue);
    return promptValue;
  };

  const validateAndEnhanceOutput = (parsedOutput) => {
    console.log("Raw parsed output:", parsedOutput);
    
    // Ensure all required fields are present
    if (!parsedOutput || !parsedOutput.title || !parsedOutput.scenes || !Array.isArray(parsedOutput.scenes)) {
      throw new Error("Invalid story format: missing required fields");
    }

    // Validate and enhance each scene
    const enhancedScenes = parsedOutput.scenes.map((scene, index) => ({
      ...scene,
      id: scene.id || `scene_${index + 1}`,
      sceneNumber: scene.sceneNumber || index + 1,
      duration: scene.duration || 5, // Default duration if not specified
      voice: scene.voice || "ElevenLabs Adam", // Default voice if not specified
      audioPrompt: scene.audioPrompt || scene.audio || "Ambient background music", // Support both audioPrompt and audio field names
      visualPrompt: scene.visualPrompt || scene.visual || "" // Support both visualPrompt and visual field names
    }));

    const enhancedOutput = {
      ...parsedOutput,
      id: parsedOutput.id || `story_${Date.now()}`,
      template: parsedOutput.template || "default",
      scenes: enhancedScenes
    };

    console.log("Enhanced output:", enhancedOutput);
    return enhancedOutput;
  };

  // Create a function-calling chain
  const functionCallingChain = model.bind({
    functions: [storyFunctionSchema],
    function_call: { name: "create_story" }
  });

  // Compose the chain using RunnableSequence
  return RunnableSequence.from([
    logInput,
    {
      formattedPrompt: formatPrompt
    },
    async (data) => {
      const promptValue = await data.formattedPrompt;
      return logPrompt(promptValue);
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

// Optional: Add a function to get tracing info for a specific run
export const getStoryTrace = functions.https.onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError(
      "unauthenticated",
      "Must be signed in to access traces"
    );
  }

  const { runId } = request.data;
  if (!runId) {
    throw new HttpsError(
      "invalid-argument",
      "Run ID is required"
    );
  }

  try {
    const user = await getAuth().getUser(auth.uid);
    if (!user.customClaims?.admin) {
      throw new HttpsError(
        "permission-denied",
        "Only admins can access traces"
      );
    }

    return {
      message: "Trace retrieval not implemented yet",
      runId
    };
  } catch (error) {
    console.error("Trace retrieval error:", error);
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
    hasFirebaseProjectId: !!process.env.FIREBASE_PROJECT_ID,
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
    response.status(404).send('Not available in production');
    return;
  }

  try {
    const testUid = 'test-user-1';
    const customToken = await getAuth().createCustomToken(testUid);
    response.json({ customToken });
  } catch (error) {
    console.error('Error creating test token:', error);
    response.status(500).json({ error: error.message });
  }
});

// Helper endpoint to get auth status (only available in emulator)
export const checkAuth = functions.https.onRequest(async (request, response) => {
  if (!process.env.FUNCTIONS_EMULATOR) {
    response.status(404).send('Not available in production');
    return;
  }

  const authHeader = request.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    response.status(401).json({ error: 'No token provided' });
    return;
  }

  try {
    const idToken = authHeader.split('Bearer ')[1];
    const decodedToken = await getAuth().verifyIdToken(idToken);
    response.json({
      uid: decodedToken.uid,
      email: decodedToken.email,
      authenticated: true
    });
  } catch (error) {
    console.error('Auth error:', error);
    response.status(401).json({ error: error.message });
  }
}); 