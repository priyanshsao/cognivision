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
		"summary":{
			Type: genai.TypeString,
			Description: "straight forward answer to the question small but enough.",
		},
		"detail": {
			Type: genai.TypeString,
			Description: "A fuller description of the scene, take each object tell its position and tell if it causes any danger or possible danger to user. -- for someone who cannot see it.",
		},
	},
	Required: []string{"summary", "detail"},
}

const iptInstructions = `You are describing a scene to a person who is blind or has low vision, so they can understand their surroundings without seeing them. Be concrete and spatial (left, right, ahead, near, far) rather than vague. Mention anything relevant to safety -- steps, curbs, obstacles, moving vehicles, open doors -- first, before anything else. Do not mention that you are an AI or that you were given an image; describe the scene directly, as a sighted companion would. Respond only with the requested JSON, nothing else.`

type Ipt struct {
	client *genai.Client
	model  string
}

type IptResponse struct {
	Summary string `json:"summary"`
	Detail  string `json:"detail"`
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

func (ipt *Ipt) Interpret(ctx context.Context, modelRes string, prompt string) (summary, detail string, err error) {
	
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
		return "", "", fmt.Errorf("unable to gemini generate content: %w", err)
	}

	parsedResp := new(IptResponse)
	if err := json.Unmarshal([]byte(resp.Text()), parsedResp); err != nil {
		return "", "", fmt.Errorf("decode gemini response: %w", err)
	}

	return parsedResp.Summary, parsedResp.Detail, nil
}