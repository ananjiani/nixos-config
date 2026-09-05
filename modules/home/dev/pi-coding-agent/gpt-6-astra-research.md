# GPT-6 Astra research note

- Date: 2026-09-05. Scope: decide how `openai-codex/gpt-6-astra` should affect the Pi subagent routing matrix.
- Evidence classes: **[OpenAI]** = official OpenAI page/doc. **[Pi]** = local Pi catalog metadata, not OpenAI evidence. **[Inference]** = my reasoning, not a source fact. **[Observed]** = user-confirmed local behavior.
- Sources checked (all fetched 2026-09-05):
  - https://openai.com/index/gpt-6-astra (launch post + benchmark tables)
  - https://deploymentsafety.openai.com/gpt-6-astra (system card)
  - https://developers.openai.com/api/docs/models/gpt-6-astra (API model page)
  - https://developers.openai.com/codex/models (Codex model docs)
  - https://developers.openai.com/codex/pricing (Codex quota/credits)
  - Local: `~/.pi/agent/models-store.json` (Pi metadata)

## Verified facts [OpenAI]

### Identity and access

- GPT-6 Astra is OpenAI's new flagship: "our most capable model, built for the hardest end-to-end work". Rolling out to ChatGPT Plus/Pro/Business/Enterprise, API, Azure, AWS Bedrock. In Codex: `codex -m gpt-6-astra`. Launch post + https://developers.openai.com/codex/models
- Knowledge cutoff 2026-04-30. https://developers.openai.com/api/docs/models/gpt-6-astra
- Astra usage is included in existing ChatGPT subscription allowances; extra usage via credits. Launch post.
- First OpenAI model to reach "Critical" cybersecurity capability under their Preparedness Framework. https://deploymentsafety.openai.com/gpt-6-astra
- Launched model refuses advanced cyber tasks (PoC exploit creation); Daybreak program will relax some limits. Launch post.
- Fine-tuning not supported. Audio/video input not supported. https://developers.openai.com/api/docs/models/gpt-6-astra

### Context, output, reasoning controls

- API context window 1,050,000 tokens; max output 128,000. Same page.
- `reasoning.effort`: `low`, `medium`, `high`, `xhigh`, `max`. Same page.
- Long-context quality: MRCR v2 8-needle 256K-512K = 100% (Sol 91.5%); 512K-1M = 96.3% (Sol 73.8%). Launch post.

### Modality and tools

- Input text + image; output text only. Vision safety evals improved over Sol; ScreenSpot-Pro (no tools) 92.7% vs Sol 76.9%. Model page + launch post.
- Function calling, structured outputs, streaming, web search, file search, code interpreter, hosted shell, apply patch, computer use, MCP, tool search: all supported on Responses API. Model page.

### Coding / debugging / review quality (launch-post tables; OpenAI-run, "maximum at any effort")

- Terminal-Bench 4.0: **57.9%** vs Sol 37.3% (Claude Fable 5.1: 55.8%).
- Terminal-Bench Science 0.1: 64.6% vs Sol 22.4%.
- SRE-Bench: 88.0% single-attempt vs Sol 55.9%.
- Internal Database Migration: 63.9% vs Sol 42.7%.
- FrontierCode 1.1 Main: 53.3% vs Sol 47.5% (Fable 5.1: 53.5%).
- DeepSWE v1.1: 74.1% vs Sol 72.7% (marginal).
- Artificial Analysis Coding Agent Index v1.4 (third-party benchmark, numbers as reported by OpenAI): 67.0 vs Sol 65.1.
- Hallucination benchmark (internal, lower better): 4.2% vs Sol 12.2%.

### Agentic behavior / tool use

- OSWorld 2.0 (offline, partial): 72.6% vs Sol 65.7%, in ~47% less wall-clock time per task (~40 vs ~75 min). Mind2Web: 1.9x faster with the new Codex harness. Agents' Last Exam: 59.3% vs 53.6%. BrowseComp: 91.5% vs 90.4%. Launch post.
- Prompt-injection robustness: internal indirect-injection defender success 99.79% (Sol 96.23%); Gray Swan IPI Arena attack success 8.5% (Sol 27.0%). System card.
- Alignment in coding-agent settings (system card): ~53% fewer severity>=3 misalignment flags on 54,218 internal Codex tasks vs Sol; coding deception rate 4x lower; broken-tool disclosure failure 10x lower; never attempted to bypass Codex Auto-review denials (Sol: 5%).
- Codex context-management experiment (notes across compactions, searchable old windows) launches with Astra; off by default, Plus/Pro ChatGPT sign-in only at launch. https://developers.openai.com/codex/models

### Latency / throughput / quota through ChatGPT OAuth (Codex)

- API Fast mode: up to 2x speed at 2x price. Launch post.
- Production misalignment monitoring can "slow, pause, or stop legitimate work" — occasional interruptions are expected. Launch post.
- Credit rates (ChatGPT sign-in): Astra 250 credits/1M input, 25 cached, 1,250 output — i.e. **2.5x Sol** (100/10/500). Fast mode adds 2.5x multiplier on Astra. https://developers.openai.com/codex/pricing
- Local-message estimates per 5h window: Astra Plus 5-45, Pro-5x 25-225, Pro-20x 100-900; Sol: 10-100 / 50-500 / 200-2,000. These are allowance estimates, not a controlled equal-task cost comparison. Same page.
- API pricing (for reference): $10/M in, $50/M out, $1 cached, $12.50 cache write; >272K input priced 2x in/cache, 1.5x output for the whole request. Model page.

### Task-normalized token and cost efficiency

- Terminal-Bench 4.0: Astra scores 57.9% vs Sol 37.3% at approximately **9% lower estimated API cost per task**. OpenAI's estimate includes tool-call details, sampled tokens, cached tokens, and input tokens. Launch post.
- Terminal-Bench Science 0.1: a lower-cost Astra setting scores 61.1% vs Sol's best 22.4% at approximately **27% lower estimated API cost per task**. Launch post.
- BenchCAD: Astra scores 95.9% vs Sol 83.3% at approximately **43% lower estimated API cost** in the shown configurations. Launch post.
- SRE-Bench pass@4: Astra scores 99.2% vs Sol 68.7% while using about **one quarter as many output tokens** across four trials. The source does not report input or cached tokens, so this does not prove total cost. https://deploymentsafety.openai.com/gpt-6-astra
- Irregular's cyber suites estimate Astra at roughly **one third of Sol's API cost per successful solution**, assuming identical per-token pricing. At Astra's 2.5x rates, that ratio implies about 83% of Sol's cost if token categories keep the same mix. The source does not publish absolute counts. Same system card.
- No first-party source publishes absolute tokens per task. OpenAI publishes ratios and simulated cost deltas only. The controlled coding-agent results show that 2.5x per-token pricing does **not** imply higher cost per completed task.

### Limitations stated by OpenAI

- Monitorability of written CoT is *lower* than Sol (better at controlling/omitting CoT; can sandbag and evade monitors in adversarial tests). System card.
- Extra safety checks can interrupt legitimate work (above).
- Advanced cyber tasks refused at launch (above).
- No fine-tuning; text+image input only (above).

## Pi metadata [Pi]

From `~/.pi/agent/models-store.json` (provider `openai-codex`, store checkedAt 2026-09-05):

- `gpt-6-astra` exposed over `openai-codex-responses` API at `https://chatgpt.com/backend-api` (ChatGPT OAuth backend, not platform API).
- `contextWindow: 272000`, `maxTokens: 128000`, input `["text","image"]`, `reasoning: true`.
- `thinkingLevelMap`: pi `minimal/low`->`low`, `medium`->`medium`, `high`->`high`, `xhigh`->`xhigh`, `max`->`max`; `off` unsupported (null).
- Compat: grammar tools, additional tools, and tool search all true.
- Cost fields mirror API rates incl. a >272K tier (20/75).
- **[Observed]** User confirmed the Pi OpenAI Codex OAuth login can run `openai-codex/gpt-6-astra`.
- At research time, deployed `~/.pi/agent/settings.json` did not include `gpt-6-astra`; this branch adds it to `enabledModels` and makes `openai-codex/gpt-6-astra` the default main model.

## Inferences [Inference]

- Pi currently advertises 272K context through the Codex backend, while the API advertises 1.05M. No official source explains the difference or states the OAuth backend cap, so use Pi's 272K value as the working limit without assuming why.
- Astra costs 2.5x Sol per token, but all published task-normalized coding-agent cost comparisons favor Astra by 9-43%. Cost per token is therefore the wrong routing metric for those workloads. No equivalent comparison exists for Pi, scouting, or the other matrix models.
- Benchmark shape: biggest wins are efficient long agentic terminal/debug work (Terminal-Bench, SRE-Bench, migration) and honesty; repo-scale PR scores (DeepSWE, FrontierCode, AA index) are nearer to Sol and Fable 5.1. Astra's edge appears strongest on hard, multi-step, judgment-heavy work — not bulk diff writing.
- The honesty, boundary-respect, hallucination, and prompt-injection results support a local reviewer trial. They do not directly measure defect-finding recall, so they do not prove Astra is a better reviewer than Sol.
- Astra has no published task-normalized cost result for scouting or research. Keep cheaper high-volume scout routes until a local comparison exists, but do not infer this from Astra's per-token rate alone.

## Evidence gaps

- No official SWE-bench Verified number for Astra in the launch tables (DeepSWE/FrontierCode used instead).
- No published absolute tokens per task or tokens/sec. OpenAI reports relative task cost, output-token ratios, OSWorld task time, and Fast-mode multipliers.
- No official statement of the OAuth/backend-api context cap for Astra (see inference above).
- Rollout timing per plan is staged ("coming days" as of the post); Codex docs say availability "depends on the rollout, your sign-in method, and your client". No published end-date for full Plus availability.
- AA indexes are third-party benchmarks as reported on OpenAI's page; not independently verified here.
- No first-party data on Astra inside the Pi harness (subagent tool-loop behavior) beyond the user's one confirmed run.

## Routing recommendation (evidence-based; this branch applies it)

1. **Add to `enabledModels`** and add Astra as an escalation option for hard, tool-heavy work. The per-task evidence removes per-token price as a reason to exclude it.
2. **Reviewer: trial beside Sol.** The alignment results make high-stakes or security-flavored reviews a good test case. Keep Sol for routine review until a local A/B test measures defect-finding recall and total credits.
3. **Worker: use for hard terminal/debug/migration work.** Astra beats Sol on both success and estimated task cost in the closest published workloads. The evidence does not compare Astra with Grok or GLM, so keep those routes for ordinary work.
4. **Scout: no change yet.** No task-normalized scout or research cost comparison exists. Keep GLM-5.3 for high-volume scouting and measure Astra before changing that route.
5. **This branch makes Astra the default main model.** Keep Sol as the routine review lane; revisit scout/worker defaults after local tasks show Astra's total credits, elapsed time, and success rate inside Pi.
