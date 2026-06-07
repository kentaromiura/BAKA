import { registerCustomLanguage, setCustomExtension } from "@pierre/diffs";
import rescriptGrammar from "./rescript.tmLanguage.json";

const rescriptRegistration = {
  ...rescriptGrammar,
  name: "rescript",
  embeddedLangs: ["javascript", "css"],
};

const rescriptLoader = () => Promise.resolve({ default: [rescriptRegistration] });

export function registerRescript() {
  registerCustomLanguage("rescript", rescriptLoader, ["res", "resi"]);
}

export function registerOdinExtension() {
  setCustomExtension("odin", "odin");
}
