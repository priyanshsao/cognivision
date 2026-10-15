package interpreter

import (
	"context"
	"encoding/json"
	"fmt"

	"google.golang.org/genai"
)

var responseSchema = &genai.Schema{
	Type: genai.TypeObject,
	Properties: map[string]*genai.Schema{
		"summary": {
			Type: genai.TypeString,
			Description: "A single short spoken sentence answering the user's question directly. " +
				"Plain, natural language -- the way you'd quickly tell a friend what's ahead, not a report. " +
				"No object-detection jargon, no listing every item found. If several things are relevant, " +
				"combine them into one flowing sentence rather than enumerating each one separately.",
		},
	},
	Required: []string{"summary"},
}

const iptInstructions = `You help a blind person understand what's in front of them, based on object-detection output (labels and pixel bounding boxes), not an image. You are their eyes for one quick question -- answer like a calm companion glancing at the scene and telling them what matters, not like a system reporting data.
 
RULES:
1. Answer only what the user actually asked. Don't describe unrelated objects.
2. One short sentence. If nothing relevant is detected, say so plainly and briefly (e.g. "Nothing in front of you on the path.") -- don't say "no objects were detected."
3. Use simple spatial words: left, right, ahead, center, close, far. Never use pixel coordinates, bounding boxes, confidence scores, or the words "detected" / "object" / "model."
4. If something could be a hazard (a step, a vehicle, an obstacle directly in the person's path), mention it first.
5. Never hedge ("it looks like," "it seems," "possibly"). State it plainly, as if you can see it clearly.
6. Combine multiple relevant items into one natural sentence -- don't list them one by one.
 
EXAMPLES OF THE STYLE YOU SHOULD MATCH:
 
Bad (too clinical, lists items like a report):
  "2 persons ahead, one on the left, one on the right, 1 person in the center of the road."
Good (same scene, same facts, natural spoken style):
  "Three people are ahead -- one on each side of you, and one straight down the center."
 
Bad:
  "Detected: chair (left), table (center). No path obstruction found."
Good:
  "There's a chair to your left and a table just ahead of it -- otherwise your path is clear."
 
Bad:
  "No objects detected matching query."
Good:
  "Nothing like that in view right now."
 
Always respond with the requested JSON only.`

type Ipt struct {
	client *genai.Client
	model  string
}

type IptResponse struct {
	Summary string `json:"summary"`
}

func NewIpt(ctx context.Context, apiKey string) (*Ipt, error) {
	config := new(genai.ClientConfig)
	config.APIKey = apiKey
	config.Backend = genai.BackendGeminiAPI

	client, err := genai.NewClient(ctx, config)
	if err != nil {
		return nil, fmt.Errorf("unable to create genai client: %w", err)
	}

	ipt := new(Ipt)
	ipt.client = client
	ipt.model = "gemini-3.5-flash-lite"

	return ipt, nil
}

func (ipt *Ipt) Interpret(ctx context.Context, modelRes string, prompt string) (summary string, err error) {

	c := new(genai.Content)
	p := new(genai.Part)
	p.Text = fmt.Sprintf("prompt: %s\n Inference Result(object detection): %s", prompt, modelRes)
	parts := []*genai.Part{p}
	c.Parts = parts

	config := &genai.GenerateContentConfig{
		SystemInstruction: &genai.Content{
			Parts: []*genai.Part{{Text: iptInstructions}},
		},
		ResponseMIMEType: "application/json",
		ResponseSchema:   responseSchema,
	}

	resp, err := ipt.client.Models.GenerateContent(ctx, ipt.model, []*genai.Content{c}, config)
	if err != nil {
		return "", fmt.Errorf("unable to gemini generate content: %w", err)
	}

	parsedResp := new(IptResponse)
	if err := json.Unmarshal([]byte(resp.Text()), parsedResp); err != nil {
		return "", fmt.Errorf("decode gemini response: %w", err)
	}

	return parsedResp.Summary, nil
}
