import js from "@eslint/js";
import googleConfig from "eslint-config-google";

export default [
  js.configs.recommended,
  {
    files: ["**/*.js"],
    ...googleConfig,
    languageOptions: {
      sourceType: "module",
      ecmaVersion: 2020,
      globals: {
        "process": "readonly",
        "console": "readonly"
      }
    },
    rules: {
      "quotes": ["error", "double"],
      "object-curly-spacing": ["error", "always"],
      "indent": ["error", 2],
      "no-unused-vars": ["warn"],
      "require-jsdoc": "off"
    },
  },
]; 