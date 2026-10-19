import { useState, useMemo } from "react";

// ════════════════════════════════════════════════════════════════════════════
// COMPLEXITY ATLAS — merged artifact
// 57 concepts · 23 frameworks (2 anchors / 12 productive / 9 metaphysical) · 15 examples · 10 methodology pages · Agentic Systems tab
// Anchored on Structural Realism × Information Theory
// ════════════════════════════════════════════════════════════════════════════

const C = {
  bg: "#0a0a0c", surface: "#111114", surface2: "#17171c", surface3: "#1c1c23",
  border: "#22222b", borderLight: "#2d2d38",
  text: "#e4e4ec", textDim: "#a8a8b8", muted: "#6b6b7d", mutedDeep: "#4a4a58",
  // Anchors
  sr: "#06b6d4", srBg: "#06b6d40d", srBorder: "#06b6d433",
  it: "#eab308", itBg: "#eab3080d", itBorder: "#eab30833",
  // Productive frameworks
  pc:  "#9333ea",   // Dynamical Systems / Stat Mech
  ait: "#22d3ee",   // Algorithmic Information Theory
  cm:  "#3b82f6",   // Computational Mechanics
  ci:  "#f97316",   // Causal Inference (Pearl)
  ce:  "#ec4899",   // Causal Emergence (Hoel)
  aif: "#84cc16",   // Active Inference (Friston)
  evo: "#10b981",   // Evolutionary Dynamics
  net: "#6366f1",   // Network Science
  th:  "#dc2626",   // Stochastic Thermodynamics
  at:  "#d946ef",   // Assembly Theory
  // Metaphysical systems
  pow: "#92400e",   // Powers / Dispositionalism
  pro: "#0d9488",   // Process Philosophy
  mec: "#475569",   // New Mechanism
  cr:  "#166534",   // Critical Realism (Bhaskar)
  sub: "#57534e",   // Substance Metaphysics
  // New productive frameworks
  ct:  "#7c3aed",   // Category Theory
  cyb: "#0891b2",   // Cybernetics
  // New metaphysical / mind frameworks
  phe: "#be185d",   // Phenomenology
  e4:  "#65a30d",   // 4E Cognition / Enactivism
  pcm: "#1e40af",   // Pancomputationalism / Information Realism (distinct deep blue)
  con: "#a16207",   // Constructor Theory (Deutsch-Marletto) — distinct burnt-amber
  // Status colors
  decision: "#fbbf24",
  open: "#94a3b8",
  accent: "#f59e0b",
};

// ─── FRAMEWORKS ──────────────────────────────────────────────────────────────
const FRAMEWORKS = {
  sr:  { label: "Structural Realism", short: "SR",  color: C.sr,  isAnchor: true, category: "anchor",
    desc: "Ladyman & Ross — relations are primary, objects are nodes in relational structure. Real patterns at multiple levels; no privileged fundamental level. The ontological anchor for what counts as real.",
    origin: "Worrall 1989 (Epistemic SR); Ladyman 1998, Ladyman & Ross 2007 'Every Thing Must Go' (Ontic SR)",
    thinkers: ["John Worrall (ESR)", "James Ladyman (OSR)", "Don Ross", "Steven French", "Daniel Dennett (Real Patterns)", "Stathis Psillos (critic)", "Tim Maudlin (critic)"],
    purpose: "Provides the ontological backbone: a defensible position that what science discovers are relational structures, not substantial things. Gives you a principled answer to 'are higher-level entities real?' (yes, as real patterns) and a vocabulary that survives theory change. What it adds: a way to take the special sciences seriously as discovering reality, without committing to either bare entities or eliminative reduction.",
    principles: [
      "What survives theory change in physics is mathematical structure, not entities — reconciles 'no miracles' realism with the pessimistic meta-induction.",
      "Objects are nothing 'over and above' nodes in relational webs; no intrinsic properties as ontological primitives.",
      "Real Patterns (Dennett): a pattern is real iff describing it compresses predictive information beyond available alternatives.",
      "Rainforest Realism (Ladyman & Ross): real patterns exist at multiple levels — physics, biology, cognition. No privileged fundamental level.",
      "Anti-reductive: the special sciences are not in-principle reducible to fundamental physics. Macro-level autonomy is real, not anthropocentric.",
      "Uses formal tools from other frameworks (CT, IT, dynamical systems) — SR is the ontological stance, not the math.",
    ],
    formulas: [],
    controversies: [
      "Newman's objection (1928): any pure-structure claim is trivially satisfied by any sufficiently large set, making SR vacuous.",
      "ESR vs OSR: is the structure all we can know (epistemic), or all there is (ontic)? Boundaries between the views are unstable.",
      "Whether the Real Patterns criterion (compressibility) is observer-relative — Dennett often read epistemically; Ladyman & Ross push ontologically.",
      "Esfeld & Lam's 'moderate' SR: relations need bearers, but bearers can lack intrinsic properties. Critics say this collapses back to substance metaphysics.",
    ],
    opposing: [
      { name: "Constructive Empiricism", who: "van Fraassen 1980", brief: "Only observable phenomena are real; theoretical structure (electrons, fields) is a useful fiction for saving phenomena. Rejects realism about anything beyond observables." },
      { name: "Substance Metaphysics", who: "Aristotelian / scholastic tradition; Lowe 2006", brief: "Objects with intrinsic properties are ontologically primary; relations are derivative. SR has the order backwards." },
      { name: "Eliminative Reductionism", who: "Various physicalist eliminativists", brief: "Only fundamental physics is fully real; higher-level patterns are ultimately eliminable. Multiple realizability is an artifact of incomplete knowledge, not a metaphysical fact." },
      { name: "Nominalism", who: "Goodman, Quine traditions", brief: "Universals and patterns are mental groupings, not features of reality. SR's 'real patterns' project human cognitive categories onto the world." },
      { name: "Standard Scientific Realism", who: "Boyd, Psillos", brief: "Theoretical entities (electrons, genes, neurons) really exist AS the entities described, not as nodes in abstract structure. Rejects SR's deflationary move on objecthood." },
      { name: "Pragmatism", who: "Putnam (late), Rorty", brief: "Realism vs anti-realism is a pseudo-problem. What matters is what works for our purposes — no need for SR's metaphysical commitments." },
    ],
  },

  it:  { label: "Information Theory", short: "IT",  color: C.it,  isAnchor: true, category: "anchor",
    desc: "Shannon and successors — entropy, mutual information, transfer entropy, KL divergence over probability distributions. Operational, computable, framework-independent. The quantitative anchor.",
    origin: "Shannon 1948 'A Mathematical Theory of Communication' (Bell Labs)",
    thinkers: ["Claude Shannon", "Norbert Wiener", "Aleksandr Khinchin", "Solomon Kullback & Richard Leibler", "Edwin Jaynes (max-entropy)", "Andrei Kolmogorov (AIT branch)", "Thomas Schreiber (transfer entropy)", "Naftali Tishby (IB)"],
    purpose: "Provides the universal quantitative toolkit for measuring uncertainty, dependence, and channel structure — substrate-free, applicable to any distribution over any alphabet. Lets you ask: how much does X tell you about Y? How much can be predicted? How much is shared? What it adds: the mathematical lingua franca that every other framework in this atlas uses to be quantitative. If you only learn one framework deeply, learn this one.",
    principles: [
      "Information is reduction of uncertainty, measured in bits (or nats). Entropy quantifies expected surprisal — the average bits required to specify an outcome.",
      "Mutual information measures statistical dependence in a substrate-independent way. Two variables are related ↔ I(X;Y) > 0.",
      "Channel capacity C bounds the maximum reliable communication rate. Shannon's coding theorem: this bound is achievable in the long-block-length limit.",
      "Data processing inequality: composition of channels can lose but never create information about a target.",
      "KL divergence is the fundamental statistical 'distance' — underlies hypothesis testing, model selection, MDL, free energy, and variational inference.",
      "Operational and substrate-independent: works equally on neurons, networks, signals, languages, gene-expression, market prices.",
    ],
    formulas: [
      { f: "H(X) = -Σ p(x) log p(x)", label: "Shannon entropy" },
      { f: "H(X|Y) = H(X,Y) − H(Y)", label: "Conditional entropy" },
      { f: "I(X;Y) = H(X) + H(Y) − H(X,Y)", label: "Mutual information" },
      { f: "I(X;Y|Z) = H(X|Z) − H(X|Y,Z)", label: "Conditional MI" },
      { f: "D_KL(P‖Q) = Σ p(x) log[p(x)/q(x)]", label: "KL divergence (relative entropy)" },
      { f: "C = max_{p(x)} I(X;Y)", label: "Channel capacity (Shannon)" },
      { f: "T(X→Y) = I(Y_{t+1}; X_t | Y_t)", label: "Transfer entropy (Schreiber 2000)" },
      { f: "EI = log N − H(E | I_D)", label: "Effective information (Hoel 2013)" },
      { f: "E = I(past; future)", label: "Excess entropy / predictive information" },
      { f: "Cμ = H(causal states)", label: "Statistical complexity (Crutchfield)" },
      { f: "h_μ = lim H(X_n | X^{n-1})", label: "Entropy rate" },
      { f: "TC(X) = Σ H(Xᵢ) − H(X)", label: "Total correlation / multi-information" },
      { f: "Φ = min_π D_KL(p ‖ p_π)", label: "Integrated information (IIT 2/3)" },
      { f: "F[q] = D_KL(q ‖ p_post) − log p(o)", label: "Variational free energy (Friston)" },
      { f: "ℐ(θ) = E[(∂_θ log p_θ)²]", label: "Fisher information" },
      { f: "K(x) = min{|p| : U(p) = x}", label: "Kolmogorov complexity (AIT)" },
      { f: "min[ I(X;T) − β I(T;Y) ]", label: "Information bottleneck (Tishby)" },
      { f: "DPI: X→Y→Z ⇒ I(X;Z) ≤ I(X;Y)", label: "Data processing inequality" },
    ],
    controversies: [
      "Is information ontological (a real feature of the world) or epistemic (observer-relative)? IT works either way but the interpretation shifts ontology.",
      "Shannon (ensembles) vs Kolmogorov (individuals) — which is fundamental? They are dual but not interchangeable; choice matters for non-ergodic settings.",
      "MI is widely conflated with causation in applied work — a major source of error in neuroscience and biology.",
      "Φ-style integration measures: do they deserve their interpretive claims (consciousness, agency), or are they mathematical objects looking for a phenomenon?",
      "Maximum entropy as inference principle (Jaynes): principled or sleight of hand?",
    ],
    opposing: [
      { name: "Algorithmic Info Theory", who: "Solomonoff, Kolmogorov, Chaitin (1960s)", brief: "Individual-object focus vs Shannon's ensembles. K(x) defined per instance, not per distribution. Sometimes seen as alternative; better viewed as complement applicable in different regimes." },
      { name: "Quantum Information", who: "von Neumann, Holevo, Werner, Bennett", brief: "Different axioms: density matrices, non-commuting observables, entanglement entropy. Classical Shannon IT recovers as a special limit. Subsumes IT at the most fundamental level." },
      { name: "Constructor Theory", who: "Deutsch & Marletto 2014–", brief: "Reformulates physics in terms of which transformations are possible vs impossible. Claims to subsume information theory as a special case. Highly contested; mostly programmatic so far." },
      { name: "Semantic Information", who: "Bar-Hillel & Carnap 1953; Floridi", brief: "Shannon ignores meaning entirely. Semantic theories try to capture truth-conditional content, not just statistical structure. Largely orthogonal but contested as 'more fundamental.'" },
      { name: "Pragmatic Information", who: "von Weizsäcker, Atmanspacher", brief: "Information is defined by the difference it makes. Critique of pure-syntax Shannon view. Useful framing in physics-philosophy but not a competing formalism." },
      { name: "Frequentist Probability", who: "Neyman, Fisher (statistics)", brief: "Probability as long-run frequency; IT's use of subjective/Bayesian probabilities is contested. Most working IT is interpretation-agnostic but interpretation matters at edges." },
    ],
  },

  pc:  { label: "Dynamical Systems & Stat Mech", short: "PC", color: C.pc, category: "productive",
    desc: "Attractors, basins, bifurcations, flows, dissipative structures, renormalization group. The physical-mathematical backbone of complexity science — what systems DO in state space.",
    origin: "Poincaré (qualitative dynamics, 1890s); Boltzmann, Gibbs (stat mech, 1870s–1900s); modern complexity: Lorenz, Prigogine, Haken, Strogatz",
    thinkers: ["Henri Poincaré", "Ludwig Boltzmann", "Edward Lorenz", "Ilya Prigogine", "Stephen Smale", "Hermann Haken", "Mitchell Feigenbaum", "Steven Strogatz", "Kenneth Wilson (RG)"],
    purpose: "Gives you the math of how systems change over time: state spaces, flows, attractors, bifurcations, stability, statistical-mechanical ensembles. Lets you ask: where does the system go, how fast, when does it qualitatively change behavior, what are the macroscopic order parameters? What it adds: the working machinery of every physics-based science — without it, claims about 'dynamics' are gestures, not analysis.",
    principles: [
      "Systems evolve via differential equations or maps in state space. Structure is in the geometry of trajectories, not in the equations themselves.",
      "Attractors, basins, bifurcations are the structural skeleton of dynamics — invariant under coordinate change.",
      "Renormalization group universality: micro details don't determine macro behavior; whole universality classes share critical exponents.",
      "Stat mech bridges micro and macro via ensembles; entropy increase reflects information loss in coarse-graining.",
      "Order parameters quantify symmetry breaking at phase transitions — the operational marker of qualitative change.",
      "Separation of timescales (slow/fast) is the fundamental reason coarse-graining works at all.",
    ],
    formulas: [
      { f: "ẋ = f(x)", label: "Autonomous state flow" },
      { f: "φᵗ : X → X", label: "Flow operator (semigroup)" },
      { f: "λ = lim (1/t) log|δx(t)/δx(0)|", label: "Lyapunov exponent (chaos)" },
      { f: "Z = Σ e^(-βH)", label: "Partition function (stat mech)" },
      { f: "S = k_B log W", label: "Boltzmann entropy" },
      { f: "x* solves f(x*) = 0", label: "Fixed point" },
      { f: "K_{n+1} = R[K_n]", label: "RG flow (Wilson)" },
    ],
    controversies: [
      "Practical limits of deterministic chaos prediction (sensitive dependence + measurement error → effective unpredictability).",
      "When stochastic vs deterministic descriptions apply — many natural systems are well-described by either.",
      "Whether equilibrium thermodynamics is adequate for living systems (Prigogine's claim: no).",
      "Extension of RG beyond physics to biology, cognition: suggestive but rigor remains contested (Mora & Bialek).",
    ],
    opposing: [
      { name: "Stochastic Process Theory", who: "Kolmogorov, Ito, Doob", brief: "Dynamics are intrinsically probabilistic, not noisy-deterministic. Strong-form stochasticity rejects the deterministic substrate of PC." },
      { name: "Quantum Mechanics", who: "von Neumann, Bell, Bohm", brief: "Classical state spaces are inadequate at small scales. Hilbert-space structure replaces classical phase space. PC is the classical limit." },
      { name: "Agent-Based / Discrete Modeling", who: "Schelling, Holland, Epstein", brief: "Continuous PDE-style descriptions are idealizations. Discrete rule-following agents are sometimes the right primitive." },
      { name: "Algorithmic / Discrete Computation", who: "Wolfram, Cellular Automata", brief: "Universe-as-computation framings reject continuous dynamics as fundamental." },
    ],
  },

  ait: { label: "Algorithmic Info Theory", short: "AIT", color: C.ait, category: "productive",
    desc: "Kolmogorov, Solomonoff, Chaitin — complexity of individual objects (not distributions). K(x) = shortest program producing x. Logical depth (Bennett). MDL. Where Shannon needs ensembles, AIT works on instances.",
    origin: "Solomonoff 1964 (induction); Kolmogorov 1965 (complexity); Chaitin 1969 (independently)",
    thinkers: ["Ray Solomonoff", "Andrei Kolmogorov", "Gregory Chaitin", "Charles Bennett (logical depth)", "Marcus Hutter (universal AI)", "Jorma Rissanen (MDL)", "Per Martin-Löf"],
    purpose: "Generalizes information theory from ensembles to individual objects: how complex is THIS string, this image, this trajectory — not its distribution? Lets you ask: what's the irreducible structural content of a particular object? Is it random, regular, or structured? What it adds: a theoretically clean (though uncomputable) definition of complexity for single objects, plus the conceptual ground for compression-based pattern detection.",
    principles: [
      "K(x) = length of shortest program producing x — complexity of an individual object, not an ensemble.",
      "Solomonoff prior: universal prior weighted by program length 2^(-|p|) — formalizes Occam's razor.",
      "Logical depth (Bennett): structural complexity = how much computation history a simple description needs. Distinct from random complexity.",
      "MDL principle: best model minimizes K(model) + K(data | model). Penalizes both overfitting and underfitting in one formalism.",
      "K is incomputable but bounded above by any specific compression. Practical AIT uses approximations (BDM, gzip, neural compression).",
    ],
    formulas: [
      { f: "K(x) = min{|p| : U(p) = x}", label: "Kolmogorov complexity" },
      { f: "K(x|y)", label: "Conditional Kolmogorov complexity" },
      { f: "M(x) = Σ_{p: U(p)=x*} 2^(-|p|)", label: "Solomonoff prior" },
      { f: "I(x:y) = K(x) + K(y) − K(x,y)", label: "Algorithmic mutual info" },
      { f: "D(x) — Bennett's logical depth", label: "Logical depth" },
      { f: "MDL: min [ K(M) + K(D|M) ]", label: "MDL principle (Rissanen)" },
    ],
    controversies: [
      "Incomputability fundamentally limits practical use — K is a normative target, not a computable quantity.",
      "Depth vs entropy: random strings have high K but low depth. Most natural complexity is depth, not randomness.",
      "Reference machine dependence: K(x) only defined up to a constant; awkward for finite instances.",
    ],
    opposing: [
      { name: "Shannon Information Theory", who: "Shannon 1948", brief: "Ensembles vs individuals. Shannon works on distributions; AIT on instances. Choice depends on whether your system is meaningfully sampled or one-of-a-kind." },
      { name: "Resource-bounded Complexity", who: "Levin, modern CC", brief: "Practical computation is bounded in time/space. Unrestricted K is too generous — real complexity should account for computational resources. Levin complexity Kt does this." },
      { name: "Stochastic Complexity (MDL)", who: "Rissanen", brief: "Alternative formalization of the same minimum-description-length intuition. More tractable but less universal. Same instinct, different math." },
    ],
  },

  cm:  { label: "Computational Mechanics", short: "CM", color: C.cm, category: "productive",
    desc: "Crutchfield's ε-machines — causal states as equivalence classes of histories with identical conditional futures. Statistical complexity Cμ. The minimal sufficient predictor; objectively privileged structural level.",
    origin: "Crutchfield & Young 1989",
    thinkers: ["James Crutchfield", "Karl Young", "Cosma Shalizi", "David Feldman", "Karoline Wiesner", "Nick Travers"],
    purpose: "Provides the algorithmic discovery procedure for the minimal sufficient predictor of any stationary stochastic process — the ε-machine — found from data, not assumed. Lets you ask: what's the smallest internal structure this process MUST have to predict its own future optimally? What's its irreducible memory? What it adds: an objectively privileged structural representation that's discovered rather than chosen — a concrete realization of structural realism.",
    principles: [
      "ε-machine: minimal sufficient predictor of a process's future from its past. Uniquely determined up to isomorphism.",
      "Causal state σ(h) = equivalence class of histories h with identical conditional future distributions. Discovered, not chosen.",
      "Statistical complexity Cμ = H(causal states) = bits of memory required for optimal prediction. The objective measure of 'how much structure does this process have?'",
      "Excess entropy E = I(past; future) ≤ Cμ. Gap measures crypticity (hidden structure).",
      "Provides an objectively privileged level of description — solves part of the observer-relativity worry that haunts other coarse-grainings.",
    ],
    formulas: [
      { f: "σ(h) = {h' : P(f|h') = P(f|h)}", label: "Causal state" },
      { f: "Cμ = H(S)", label: "Statistical complexity" },
      { f: "E = I(past; future)", label: "Excess entropy" },
      { f: "h_μ = lim H(X_n | X^{n-1})", label: "Entropy rate" },
      { f: "Cμ ≥ E ≥ 0", label: "Hierarchy" },
    ],
    controversies: [
      "Practical estimation of causal states from finite data: model-selection problem with no universally agreed solution.",
      "State-space explosion in high dimensions limits empirical applicability.",
      "Uniqueness only up to isomorphism — interpretation of states is still framework-relative.",
    ],
    opposing: [
      { name: "Hidden Markov Models", who: "Baum, Welch 1960s; ubiquitous", brief: "Older, more flexible, less principled. HMMs don't claim minimality; ε-machines do." },
      { name: "Predictive State Representations", who: "Littman, Sutton, Singh 2001", brief: "Same minimal-sufficient-predictor intuition, different formalism (continuous states, RL roots). Largely compatible." },
      { name: "Reservoir Computing", who: "Jaeger, Maass 2001–2002", brief: "Random recurrent networks as universal computational substrate. Different way to capture temporal structure; less principled but very practical." },
    ],
  },

  ci:  { label: "Causal Inference", short: "CI", color: C.ci, category: "productive",
    desc: "Pearl's do-calculus, structural causal models, identifiability. The operational framework for distinguishing causation from correlation via interventions. Three-rung ladder: observe, intervene, counterfactual.",
    origin: "Wright 1920s (path analysis); Pearl 1980s–2000s ('Causality' 2000, 2009)",
    thinkers: ["Sewall Wright", "Judea Pearl", "Donald Rubin", "Peter Spirtes", "Clark Glymour", "James Robins", "Bernhard Schölkopf"],
    purpose: "Gives you the machinery to distinguish correlation from causation, and to compute the consequences of hypothetical interventions even from observational data. Lets you ask: would Y change if I forced X to take value x? Which observed associations are causal vs. confounded? Where can I generalize from data? What it adds: the only mature, formally rigorous framework for moving from 'this is associated with that' to 'this causes that' — the mathematics behind modern epidemiology, econometrics, and ML safety.",
    principles: [
      "Three-rung ladder: (1) Observation P(Y|X), (2) Intervention P(Y|do(X)), (3) Counterfactual P(Y_x|X=x',Y=y'). Each rung requires strictly more structure.",
      "Structural Causal Models (SCMs): variables linked by deterministic structural equations + exogenous noise. The do-operator severs incoming edges, modeling intervention.",
      "Backdoor criterion: blocks confounding paths. If a sufficient adjustment set Z satisfies the criterion, P(Y|do(X)) is identifiable from P(Y|X,Z).",
      "d-separation: graphical criterion for conditional independence read directly off the DAG. Bridge between graph structure and probability statements.",
      "Identifiability: not all causal effects are identifiable from observational data alone — some need experiments. Pearl's do-calculus tells you which.",
    ],
    formulas: [
      { f: "Y = f(parents, ε)", label: "Structural equation in SCM" },
      { f: "P(Y | do(X = x))", label: "Interventional distribution" },
      { f: "P(Y|do(X)) = Σ_z P(Y|X,Z=z) P(Z=z)", label: "Backdoor adjustment" },
      { f: "P(Y_x | X = x', Y = y')", label: "Counterfactual probability" },
      { f: "ATE = E[Y | do(X=1)] − E[Y | do(X=0)]", label: "Average treatment effect" },
    ],
    controversies: [
      "Acyclic assumption excludes feedback systems. Cyclic causal models exist but are less developed.",
      "'No causes in, no causes out' (Cartwright): all causal inference depends on assumed background causal claims. Pure observational identifiability is rare.",
      "Pearl SCMs vs Rubin Causal Model (potential outcomes): two largely-equivalent but stylistically different frameworks; users often partisan.",
      "Many real-world DAGs are unknown — model misspecification is the dominant source of error in practice.",
    ],
    opposing: [
      { name: "Humean Regularity Theory", who: "Hume 1748; Mackie (INUS conditions)", brief: "No causation beyond constant conjunction and contiguity. SCMs add structure Hume would deny is justified." },
      { name: "Counterfactual Theory", who: "Lewis 1973; Stalnaker", brief: "Causation defined via possible-worlds counterfactuals, not SCMs. Pearl's counterfactual rung is partly Lewis-compatible but uses structural rather than modal semantics." },
      { name: "Process/Transference Theory", who: "Salmon 1984; Dowe 2000", brief: "Causation = transfer of conserved physical quantities (energy, momentum) along world lines. Physical-process-based, not statistical. Compatible with PC's process framing." },
      { name: "Dispositionalism / Powers", who: "Mumford, Anjum, Bird", brief: "Things have intrinsic causal powers / dispositions. Causation is the manifestation of these powers, not statistical regularity or graph structure." },
      { name: "Causal Pluralism", who: "Cartwright 2007", brief: "There is no single thing called 'causation' — multiple irreducibly different concepts depending on context (mechanism, counterfactual, process)." },
      { name: "Granger Causality", who: "Granger 1969", brief: "Predictive precedence in time series. Weaker than Pearl's causation (no intervention); strong enough for many forecasting applications. Often misunderstood as full causation." },
    ],
  },

  ce:  { label: "Causal Emergence", short: "CE", color: C.ce, category: "productive",
    desc: "Hoel's effective information — for some systems, macro scale has strictly greater EI than micro. Multi-scale extension of interventionism. Quantitative, computable claim that emergence is real.",
    origin: "Hoel, Albantakis & Tononi 2013 PNAS; Hoel 2017",
    thinkers: ["Erik Hoel", "Larissa Albantakis", "Giulio Tononi", "Pavel Chvykov (critic-collaborator)", "Renzo Comolatti"],
    purpose: "Lets you detect — quantitatively, from data — which scale of description has the most causal power in a system, possibly the macro scale rather than the micro. Lets you ask: is the causally privileged level here molecular, cellular, individual, or collective? Where is intervention most informative? What it adds: a computable test for whether 'emergence' is genuine causal autonomy or merely convenient coarse-graining — and the empirical machinery to act on the answer.",
    principles: [
      "Effective Information EI = I(I_D; E_D) under a uniform intervention distribution I_D. Quantifies how informative interventions are about effects.",
      "EI decomposes as determinism − degeneracy. Both increase EI; their gap is the precise structure of causation at that scale.",
      "Causal Emergence: there exists a coarse-graining π such that EI(π(X)) > EI(X). Computable from transition matrix.",
      "Compatible with physicalism: macro EI > micro EI does NOT entail downward causation. Strong emergence is NOT being claimed.",
      "Macro level is 'causally privileged' for some systems — those where coarse-graining sharpens the causal model.",
    ],
    formulas: [
      { f: "EI(S) = I(I_D; E_D)", label: "Effective information" },
      { f: "EI = log N − H(E | I_D)", label: "EI decomposition (det − deg)" },
      { f: "CE: ∃π, EI(π(X)) > EI(X)", label: "Causal emergence condition" },
    ],
    controversies: [
      "Uniform intervention prior is a methodological choice. Different priors can flip the EI ordering between scales.",
      "Eberhardt & Lee critique: CE may be partly an artifact of the prior, not an objective feature.",
      "'Causal emergence' terminology overpromises — strictly within physicalism, no downward causation claimed.",
      "Hoel has acknowledged some of these methodological worries in later work; the framework is still evolving.",
    ],
    opposing: [
      { name: "Eliminativism", who: "Various physicalists", brief: "Macro causation is always micro causation in disguise. The macro EI advantage is methodological convenience, not metaphysical novelty." },
      { name: "Eberhardt & Lee critique", who: "Eberhardt et al. 2017", brief: "CE results depend sensitively on the choice of intervention distribution. The uniform prior is unmotivated; alternative priors give different scale orderings." },
      { name: "Partial Information Decomposition", who: "Williams & Beer 2010; Rosas et al.", brief: "Alternative decomposition of multi-variate information into redundant/unique/synergistic components. Different lens on the same multi-scale phenomena." },
      { name: "Pearl-only Identifiability", who: "Pearl school", brief: "Prefer to do causal inference at the level where the model is well-specified, not search across scales. CE looks like model-selection in disguise." },
    ],
  },

  aif: { label: "Active Inference (FEP)", short: "AIF", color: C.aif, category: "productive",
    desc: "Friston's free energy principle — systems with Markov blankets that persist must minimize variational free energy. Contested universality claim, but generative framework for agency, life, mind.",
    origin: "Friston 2006 onward (Friston, Kilner, Harrison 2006)",
    thinkers: ["Karl Friston", "Thomas Parr", "Giovanni Pezzulo", "Christopher Buckley", "Lancelot Da Costa", "Maxwell Ramstead"],
    purpose: "Provides a unifying mathematical account of perception, action, learning, and self-maintenance as one operation: minimizing variational free energy under a generative model. Lets you ask: what would a system have to predict and infer to maintain its characteristic states? What does the system's behavior tell you about its implicit model of the world? What it adds: the most ambitious current candidate for a unified theory of agency in living and cognitive systems — alongside its serious technical contestations.",
    principles: [
      "Systems with persistent Markov blankets must minimize variational free energy F[q] — equivalently, they implicitly act as Bayesian inference machines about their environment.",
      "Perception = inference about hidden causes of sensations. Action = inference-guided sampling to confirm predictions. Learning = inference over parameters. ONE objective.",
      "Free energy is an UPPER BOUND on surprise (negative log evidence). Minimizing F minimizes surprise without computing the intractable evidence directly.",
      "Expected free energy G drives action selection: agents prefer policies that minimize anticipated free energy — unifies exploration (info gain) and exploitation (preference satisfaction).",
      "Claimed as a universal principle: anything that persists has a Markov blanket and therefore (implicitly) minimizes free energy. Sweeping but contested.",
    ],
    formulas: [
      { f: "F[q] = D_KL(q ‖ p_posterior) − log p(o)", label: "Variational free energy" },
      { f: "F ≥ −log p(o)", label: "Variational bound on neg-log-evidence" },
      { f: "G(π) = E_q[F(o,s)]", label: "Expected free energy (action selection)" },
      { f: "MB(X) = pa(X) ∪ ch(X) ∪ pa(ch(X))", label: "Markov blanket" },
    ],
    controversies: [
      "Is FEP a substantive empirical claim or near-tautology? Sun & Firestone 2020, Andrews 2021, Litwin & Miłkowski argue tautology.",
      "Aguilera et al. 2022: in many stochastic systems, Markov blankets may not exist or may be non-unique. Friston's mathematical commitments are often unacknowledged.",
      "Many 'AIF' results are generic Bayesian / predictive-coding results, not specific to FEP.",
      "Whether minimizing variational FREE ENERGY is empirically distinguishable from any other Bayesian update rule.",
      "Conflation of variational (information) free energy with thermodynamic (physical) free energy in pop accounts.",
    ],
    opposing: [
      { name: "Predictive Coding (non-FEP)", who: "Rao & Ballard 1999; Clark 2013", brief: "Same coding mechanism (predictions + error signals) without the universal-minimization claim. More tractable, less metaphysically ambitious." },
      { name: "Reinforcement Learning", who: "Sutton & Barto", brief: "Reward maximization, not surprise minimization. Different optimization target. AIF and RL can sometimes be related (reward = preference) but the framings are distinct." },
      { name: "Embodied / Enactive Cognition", who: "Varela, Thompson, Rosch", brief: "Rejects predictive processing as primary. Mind is sensorimotor coupling with the world, not internal models of it." },
      { name: "Aguilera et al. critique", who: "Aguilera, Millidge, Tschantz, Buckley 2022", brief: "Direct technical critique: Markov blankets in stochastic settings are often non-unique or non-existent. Friston's particular assumptions are restrictive." },
      { name: "Andrews tautology argument", who: "Andrews 2021", brief: "FEP claims are derivable from any consistent inference framework. The 'principle' adds no falsifiable content beyond standard Bayesian inference." },
    ],
  },

  evo: { label: "Evolutionary Dynamics", short: "EVO", color: C.evo, category: "productive",
    desc: "Fisher, Wright, Hamilton, Price, Maynard Smith, Nowak, Lenski — formal theory of how populations of replicators with variation, heritability, and differential fitness change over time. Substrate-independent: biological, cultural, technological, and immunological evolution all instantiate the same mathematical machinery.",
    origin: "Darwin 1859 (qualitative); Fisher 1930, Wright 1931, Haldane 1932 (mathematical synthesis)",
    thinkers: ["Charles Darwin", "Ronald Fisher", "Sewall Wright", "J.B.S. Haldane", "William Hamilton", "George Price", "John Maynard Smith", "Eörs Szathmáry", "Martin Nowak", "Richard Lenski"],
    purpose: "Gives you the dynamics of populations under variation, heritability, and differential reproduction — the only mature theory of how complex functional structure arises without a designer. Lets you ask: which variants persist? How fast does adaptation happen? When does selection vs. drift dominate? What can selection NOT explain? What it adds: the substrate-independent logic of cumulative selection — applicable to genes, languages, technologies, ideas, and (increasingly) AI systems.",
    principles: [
      "Lewontin's three conditions: variation, heritability, differential fitness based on traits. Any system meeting all three WILL evolve — biological, cultural, technological, computational.",
      "Replicator equation ẋᵢ = xᵢ(fᵢ − ⟨f⟩) describes population dynamics under selection. Fixed points are evolutionarily stable strategies (Maynard Smith).",
      "Price equation decomposes total trait change into selection and transmission components — algebraically rigorous statement of evolutionary change.",
      "Selection-mutation-drift triad: selection biases, mutation generates variation, drift adds noise. All three operate simultaneously.",
      "Multi-level selection: selection operates at multiple levels (gene, individual, group, species) simultaneously. The 'unit of selection' is itself empirical and can shift (major transitions).",
      "Fitness landscapes (Wright) — adaptive peaks, valleys, ridges. Populations climb local peaks; escape requires drift or environmental change.",
    ],
    formulas: [
      { f: "ẋᵢ = xᵢ(fᵢ − ⟨f⟩)", label: "Replicator equation" },
      { f: "ΔE[z] = Cov(w,z)/⟨w⟩ + E[w·Δz]/⟨w⟩", label: "Price equation" },
      { f: "rb > c", label: "Hamilton's rule (kin selection)" },
      { f: "ESS: f(p*,p*) > f(p,p*) for p ≠ p*", label: "Evolutionarily stable strategy" },
      { f: "ΔF̄ = Var(F)/F̄", label: "Fisher's fundamental theorem" },
    ],
    controversies: [
      "Adaptationism vs Gould & Lewontin's spandrels critique: how much of biological structure is 'designed by selection' vs free-rider on other traits?",
      "Levels of selection: strict gene-centrism (Dawkins) vs multi-level (Wilson, Sober). Genuine empirical question.",
      "Extended Evolutionary Synthesis (EES) vs Modern Synthesis (MS): how much do niche construction, plasticity, and inheritance beyond genes change the picture?",
      "Whether cultural evolution is 'really' evolution in the same mathematical sense, or analogical.",
    ],
    opposing: [
      { name: "Neutralism", who: "Kimura 1968", brief: "Most molecular change is drift, not selection. Selection acts strongly only on a minority of substitutions. Hugely successful for molecular evolution; disputed elsewhere." },
      { name: "Saltationism / Hopeful Monsters", who: "Goldschmidt 1940; Schindewolf", brief: "Evolution proceeds by large jumps, not gradualism. Mostly rejected mid-20th C; partly revived in evo-devo (small developmental changes → large phenotypic effects)." },
      { name: "Epigenetic / Lamarckian", who: "Modern epigenetic-inheritance proponents", brief: "Soft inheritance: acquired traits can be transmitted. Limited empirical role; rejected as central by mainstream EVO but increasingly discussed at margins." },
      { name: "Strict Gene-Centrism", who: "Dawkins 1976", brief: "Genes are the only true units of selection; organisms are 'survival machines.' Rejects multi-level selection. Largely opposed by modern multilevel theorists." },
      { name: "Punctuated Equilibrium", who: "Eldredge & Gould 1972", brief: "Long stasis interrupted by rapid speciation. Empirically supported for fossil record but its theoretical novelty over gradualism is contested." },
      { name: "Niche Construction Theory", who: "Odling-Smee, Laland, Feldman 2003", brief: "Organisms shape their selection environments — co-evolution of organism and niche. Extends EVO; some advocates claim it replaces gene-centric MS." },
    ],
  },

  net: { label: "Network Science", short: "NET", color: C.net, category: "productive",
    desc: "Erdős, Watts-Strogatz, Barabási, Newman, Strogatz — formal theory of relational structure as graphs. Degree distributions, modularity, percolation, scale-free, community detection. The mathematical backbone for any system where 'who connects to whom' is the dominant structural fact.",
    origin: "Erdős & Rényi 1959 (random graphs); Watts & Strogatz 1998 (small-world); Barabási & Albert 1999 (scale-free)",
    thinkers: ["Paul Erdős", "Alfréd Rényi", "Duncan Watts", "Steven Strogatz", "Albert-László Barabási", "Réka Albert", "Mark Newman", "Mark Granovetter", "Aaron Clauset (critic)"],
    purpose: "Provides the formal tools for analyzing systems as graphs of nodes and edges — degree distributions, community structure, spectral properties, dynamics on networks. Lets you ask: who's connected to whom, how robust is the topology, where does information or contagion spread fastest, what are the structural communities? What it adds: a concrete computational realization of structural realism — and the workhorse method whenever 'who relates to whom' matters more than 'what each thing is.'",
    principles: [
      "Networks = graphs: nodes + edges, possibly directed, weighted, multi-relational. Topology is the structure.",
      "Real networks are usually neither random nor regular: small-world (low diameter + high clustering), often scale-free (power-law degree).",
      "Topology shapes dynamics: epidemic thresholds, synchronization, robustness, controllability all depend on graph structure.",
      "Modularity / community structure is ubiquitous — networks decompose into densely connected subgroups (Louvain, Leiden algorithms).",
      "Robustness vs vulnerability tradeoff: scale-free networks are robust to random failure but fragile to targeted attack.",
      "Networks bridge directly to SR — they ARE relational structure made explicit, with computable topological invariants.",
    ],
    formulas: [
      { f: "P(k) ~ k^(-γ), γ ∈ (2,3)", label: "Scale-free degree distribution" },
      { f: "C = clustering coefficient", label: "Clustering" },
      { f: "ℓ ~ log N / log⟨k⟩", label: "Small-world path length" },
      { f: "Q = Σ_c [eᶜ − (aᶜ)²]", label: "Modularity (Newman-Girvan)" },
      { f: "p_c percolation threshold", label: "Percolation transition" },
      { f: "λ_max (spectral radius)", label: "Stability/spreading dynamics" },
    ],
    controversies: [
      "Broido & Clauset 2019: statistical tests reject scale-free hypothesis for many networks claimed to be scale-free. The 'scale-free era' may have over-fit.",
      "When are pairwise graphs sufficient vs hypergraphs / higher-order interactions needed?",
      "Statistical inference on networks is hard — observations are non-independent. Most graph statistics are biased on real data.",
      "Community detection: many algorithms, no universally correct partition. Reflects fundamental observer-dependence at boundaries.",
    ],
    opposing: [
      { name: "Hypergraph Theory", who: "Berge 1973; modern higher-order network science", brief: "Pairwise edges are insufficient for many systems (proteins, brain regions, social settings). Hypergraphs and simplicial complexes generalize networks." },
      { name: "Topological Data Analysis", who: "Carlsson 2009; persistent homology", brief: "Simplicial complexes and homology beyond graphs. Captures multi-scale topological features (loops, voids) that graph statistics miss." },
      { name: "Geometric / Continuous Models", who: "Various; Penrose tilings; manifold learning", brief: "Networks are discretizations of underlying continuous structure (metric space, manifold). Geometry is the primary thing; network is the sampling." },
      { name: "Statistical Relational Learning", who: "Getoor, Koller, Domingos", brief: "Alternative formalization combining logic, networks, and probability. Different starting point: knowledge bases rather than graphs." },
    ],
  },

  th:  { label: "Stochastic Thermodynamics", short: "TH", color: C.th, category: "productive",
    desc: "Jarzynski, Crooks, Seifert, England — modern non-equilibrium statistical mechanics with rigorous fluctuation theorems. Landauer's principle, dissipative adaptation, information-thermodynamics unification. Turns Prigogine's qualitative picture of dissipative structures into precise math.",
    origin: "Jarzynski 1997 (equality); Crooks 1999 (fluctuation theorem); Seifert 2005– (stochastic entropy production)",
    thinkers: ["Christopher Jarzynski", "Gavin Crooks", "Udo Seifert", "Massimiliano Esposito", "Jeremy England", "Charles Bennett (Landauer/information)", "Rolf Landauer"],
    purpose: "Extends classical thermodynamics to small, far-from-equilibrium systems with stochastic fluctuations — connecting heat, work, information, and computation via exact fluctuation theorems. Lets you ask: what's the minimum energy cost of this computation, measurement, or self-maintenance? How does information acquisition relate to dissipation? What it adds: the rigorous bridge between physics and information — including Landauer's bound, Jarzynski equality, and the modern thermodynamics of prediction (Still et al.).",
    principles: [
      "Fluctuation theorems: rigorous statements linking forward and reverse trajectory probabilities to entropy production. P(σ)/P(-σ) = e^σ.",
      "Trajectory-level entropy production: thermodynamics extends to individual realizations, not just averages.",
      "Landauer's principle: erasing one bit dissipates at least kT ln 2 of heat. Information has thermodynamic cost.",
      "Dissipative adaptation (England 2013): matter under sustained driving tends to self-organize toward configurations that better absorb and dissipate the driving energy.",
      "Information-thermodynamics unification: information processing IS entropy management. Maxwell's demon is an information engine.",
    ],
    formulas: [
      { f: "⟨e^(-βW)⟩ = e^(-βΔF)", label: "Jarzynski equality" },
      { f: "P(σ)/P(-σ) = e^σ", label: "Crooks fluctuation theorem" },
      { f: "σ_irr ≥ 0", label: "Second law (trajectory-level)" },
      { f: "W_min ≥ kT ln 2", label: "Landauer bound (per bit erased)" },
      { f: "dS_tot/dt = dS_sys/dt + dS_env/dt ≥ 0", label: "Total entropy production" },
    ],
    controversies: [
      "Generality of fluctuation theorems beyond Markovian dynamics — non-Markovian extensions exist but are framework-dependent.",
      "England's dissipative adaptation: theoretically suggestive but experimental support for the strong claim is sparse.",
      "Whether information truly has intrinsic energy cost or only contextually (some argue Landauer is more subtle than usually stated).",
      "Quantum stochastic thermodynamics: how to extend cleanly to quantum systems is actively contested.",
    ],
    opposing: [
      { name: "Equilibrium Thermodynamics", who: "Gibbs, Clausius traditions", brief: "Still the workhorse for most calculations. Equilibrium ensembles cover much of stat mech without needing trajectory-level machinery." },
      { name: "Quantum Thermodynamics", who: "Kosloff, Aspuru-Guzik", brief: "Quantum systems have non-classical state space and coherence. Different axioms; many classical TH theorems don't transfer cleanly." },
      { name: "Information Thermodynamics Skeptics", who: "Norton, Maroney", brief: "Argue Landauer's principle is more subtle than usually claimed; information per se has no thermodynamic cost — only specific physical implementations do." },
    ],
  },

  at:  { label: "Assembly Theory", short: "AT", color: C.at, category: "productive",
    desc: "Walker & Cronin (2023, contested) — assembly index A(x) counts the minimum number of joining operations to construct x from primitives, reusing previously-constructed parts. Combined with copy number, proposed as a substrate-independent marker of selection / cumulative process. Applications: life detection, technology lineages, molecular complexity.",
    origin: "Marshall et al. 2017 (molecular assembly index); Walker, Cronin et al. 2021–2023 ('assembly theory' formalization)",
    thinkers: ["Sara Walker", "Lee Cronin", "Stuart Marshall", "Cole Mathis", "Hector Zenil (critic-collaborator)", "Adam, Hazen, Kempes (critics)"],
    purpose: "Proposes a single quantitative signature (Assembly Index × Copy Number) intended to distinguish products of selection or design from products of background chemistry — substrate-free in claim. Lets you ask: in this chemical or technological sample, are there structures complex enough and abundant enough to indicate non-random construction? What it adds: a candidate empirical biosignature usable without prior knowledge of the system's chemistry — though its independence from compression-based measures remains contested.",
    principles: [
      "Assembly index A(x): minimum number of construction steps to make object x from primitives, where each step can reuse already-constructed parts. A is the 'compressed history' of the object.",
      "Copy number N(x): how many instances of x are observed in a system. High N alone is not interesting; high A × N IS.",
      "A × N proposed as marker of selection: random chemistry produces low-A objects in many copies, OR high-A objects in few copies. Both high together = cumulative process.",
      "Substrate-independent (per claim): same machinery should work for molecules, technologies, language.",
      "Operationally testable: assembly index can be measured for real molecules via mass spectrometry / NMR.",
    ],
    formulas: [
      { f: "A(x) = shortest construction path", label: "Assembly index" },
      { f: "N(x) = copy number", label: "Copy number" },
      { f: "Assembly = A(x) × N(x)", label: "Selection signature (informal)" },
    ],
    controversies: [
      "Adam, Marletto, Hazen, Kempes critiques: AT recapitulates Kolmogorov complexity / logical depth / functional information in new language. Not operationally distinct from existing measures.",
      "Walker & Cronin's response: AT is operationally distinct because it is computable (unlike K) and physically measurable.",
      "Whether the substrate-independence claim is actually justified.",
      "Whether the 'life detection' applications work as claimed.",
    ],
    opposing: [
      { name: "Algorithmic Info Theory", who: "Kolmogorov, Bennett (logical depth)", brief: "AT is arguably a special, computable case of K and depth. Critics argue it adds vocabulary without adding theory." },
      { name: "Functional Information", who: "Hazen et al. 2007", brief: "Alternative substrate-independent complexity measure: bits required to specify function. Predates AT and overlaps strongly. Hazen has criticized AT for not adequately citing this lineage." },
      { name: "Standard MDL / Bayesian Model Selection", who: "Rissanen; broad Bayesian literature", brief: "Any good generative model implicitly captures the 'assembly' history of its data. AT's claims are implicit in standard model selection." },
      { name: "Biology-Internal Complexity Measures", who: "Adami, Ofria; bioinformatics tradition", brief: "Prefer measures grounded in biology (genome content, regulatory network complexity) over universal-substrate claims." },
    ],
  },

  pow: { label: "Powers / Dispositionalism", short: "POW", color: C.pow, category: "metaphysical",
    desc: "Mumford, Bird, Anjum, Cartwright — properties ARE causal powers / dispositions, individuated by what they would do under what conditions. Causation = manifestation of powers when conditions are met. Modern revival of Aristotelian dunamis as the metaphysical ground for the laws of nature.",
    origin: "Aristotle (dunamis); modern revival: Harré & Madden 1975 'Causal Powers'; Mumford 1998 'Dispositions'; Bird 2007 'Nature's Metaphysics'",
    thinkers: ["Rom Harré & E.H. Madden (revival)", "Stephen Mumford", "Alexander Bird", "Rani Anjum", "Nancy Cartwright", "George Molnar", "Neil Williams", "C.B. Martin"],
    purpose: "Provides an ontology in which causation is real and intrinsic: properties ARE causal powers, manifesting under triggering conditions. Lets you ask: what dispositions does this system have? What WOULD it do under conditions it hasn't yet encountered? What it adds: a positive metaphysics of causation that grounds Pearl's interventional framework — causation isn't just counterfactual regularity but the operation of real powers in the world.",
    principles: [
      "Properties are essentially powers/dispositions: their identity is exhausted by what they would do under specified conditions. Mass IS the disposition to resist acceleration; charge IS the disposition to attract/repel.",
      "Causation is the manifestation of powers under appropriate stimulus conditions — not Humean constant conjunction.",
      "Laws of nature are not external impositions but descriptions of the patterns generated by powers' essential natures (Bird's Dispositional Essentialism).",
      "Powers can be present without manifesting (latency) and can interfere with each other (mutual masking). Tendencies and 'ceteris paribus' are first-class.",
      "Cartwright: 'How the Laws of Physics Lie' — laws describe idealized power-manifestations; nature is a patchwork of locally operating powers.",
      "Strong fit with complexity science: attractors, basins, and bifurcations look like dispositional structures — what the system WOULD do under various conditions.",
    ],
    formulas: [],
    controversies: [
      "Pure-power vs categorical-base views (Bird vs Heil): are powers ontologically primitive, or do they have intrinsic categorical bases manifesting in dispositional roles?",
      "How do powers compose? Vector addition (Mumford & Anjum) or richer composition logic? No agreed answer.",
      "Conditional analysis of dispositions: D(x) ↔ (S(x) □→ R(x))? Defeated by Martin's 'finkish' objections; replacement analyses contested.",
      "Whether the conceptual identity of a power requires its complete manifestation profile (potentially infinite).",
    ],
    opposing: [
      { name: "Humean Regularity Theory", who: "Hume 1748; Lewis (Humean supervenience)", brief: "There are no powers, only patterns of constant conjunction. Properties have no intrinsic dispositional natures — the world is just one damn thing after another." },
      { name: "Categoricalism / Neo-Humeanism", who: "Armstrong 1983; Lewis 1986", brief: "Properties are intrinsic qualities; their causal roles are contingently attached by laws. Powers wrongly essentialize what is contingent." },
      { name: "Structural Realism", who: "Ladyman & Ross 2007", brief: "Properties are nodes in relational structure — not bearers of intrinsic essences. Direct rival to POW: relations vs intrinsic natures as the metaphysical ground." },
      { name: "Process Philosophy", who: "Whitehead, Bergson, Rescher", brief: "Powers presuppose substance-bearers; process metaphysics rejects that ontology entirely. Becoming, not powers, is fundamental." },
    ],
  },

  pro: { label: "Process Philosophy", short: "PRO", color: C.pro, category: "metaphysical",
    desc: "Whitehead, Bergson; modern revival in Dupré, Nicholson, Seibt — reality is fundamentally process, not substance. Events/becomings are primary; 'things' are abstractions from stable process-patterns. Direct fit with dynamical systems, metabolism, and self-organization.",
    origin: "Heraclitus (πάντα ῥεῖ); Bergson 1907 'Creative Evolution'; Whitehead 1929 'Process and Reality'; modern revival: Rescher 1996, Seibt 2003, Dupré 2012–, Nicholson 2018",
    thinkers: ["Alfred North Whitehead", "Henri Bergson", "Nicholas Rescher", "Johanna Seibt", "John Dupré (process biology)", "Daniel Nicholson", "Gilles Deleuze (extension)"],
    purpose: "Provides an ontology in which becoming is fundamental and substance derivative — what's real is process, pattern in flow, not static entities. Lets you ask: what would this phenomenon look like if I stopped treating it as a thing and started treating it as an ongoing activity? Which 'objects' are actually stabilized processes? What it adds: the metaphysical framework most compatible with modern dynamical biology (Dupré, Nicholson), dissipative structures (Prigogine), and autopoiesis (Maturana-Varela) — and the most natural home for understanding organisms as flows.",
    principles: [
      "Reality is fundamentally process: change, flow, becoming. 'Substances' are abstractions — convenient recognition of more or less stable process-bundles.",
      "Events / actual occasions are the basic ontological units (Whitehead). A 'thing' is a longitudinal pattern of events with sufficient stability — Whitehead's 'society.'",
      "Becoming is ontologically primary; being is derivative. Opposite priority order from substance metaphysics.",
      "Causation IS process — the past constitutively shapes the present via continuous prehension (Whitehead) or duration (Bergson).",
      "Creativity is fundamental: genuine novelty is real, not illusory (Whitehead's 'ultimate' category). Closely related to strong emergence.",
      "Modern process biology (Dupré, Nicholson): organisms are not things but stabilized patterns of metabolic flux. Directly bridges to TH, EVO, AIF.",
    ],
    formulas: [],
    controversies: [
      "Is process ontology genuinely incompatible with substance ontology, or just a different vocabulary for the same reality?",
      "The status of stable structures: are they really processes, or are they just slow events? Where does 'fast change' become 'persistent thing'?",
      "Whether Whitehead's specific metaphysics (creativity, eternal objects, God) is essential or removable scaffolding for the process-ontological core.",
      "How process biology relates to standard molecular biology — complement or replacement?",
    ],
    opposing: [
      { name: "Substance Metaphysics", who: "Aristotelian, Neo-Aristotelian (Lowe, Tahko)", brief: "Things with intrinsic natures are primary; processes are what things do. Direct rival." },
      { name: "Eliminativist Physicalism", who: "Various physicalist reductionists", brief: "Only fundamental physics is real; both 'process' and 'substance' are higher-level fictions of the same kind." },
      { name: "Mereological Universalism", who: "Lewis, Sider 4D ontology", brief: "Any collection of parts composes a whole at any time slice — denies process-priority by treating spacetime as block." },
      { name: "Standard Substance-Functional Hybrid", who: "Most working scientists implicitly", brief: "Use substance vocabulary for entities + functional/dynamical vocabulary for activities. Pragmatic mixture rather than committed metaphysics — and process metaphysicians argue this is incoherent." },
    ],
  },

  mec: { label: "New Mechanism", short: "MEC", color: C.mec, category: "metaphysical",
    desc: "Machamer, Darden, Craver, Bechtel, Glennan — a mechanism is an organized arrangement of entities and activities producing a phenomenon. Explanation IS mechanism-identification. The dominant philosophy of explanation in molecular biology and cognitive neuroscience.",
    origin: "Bechtel & Richardson 1993; Machamer, Darden & Craver 2000 'Thinking About Mechanisms'; Glennan 1996, 2017",
    thinkers: ["Peter Machamer", "Lindley Darden", "Carl Craver", "William Bechtel", "Robert Richardson", "Stuart Glennan", "Lindley Darden"],
    purpose: "Provides the dominant philosophy of explanation in contemporary biology and neuroscience: phenomena are explained by identifying the mechanism — entities + activities organized to produce them. Lets you ask: what are the components, what are they doing, and how is the organization producing the observed phenomenon? What it adds: a clear positive account of what scientific explanation IS in working biology — and a metaphysics that takes the actual practice of biology and neuroscience seriously rather than imposing a physics-shaped template.",
    principles: [
      "A mechanism is entities + activities organized to produce a phenomenon (the 'MDC formula'). Not just structure or function alone — the combination.",
      "Explanation = describing the responsible mechanism. To explain phenomenon X is to identify the mechanism that produces X under typical conditions.",
      "Mechanisms are multi-level: each component has its own component-mechanism, recursively. Mechanistic explanation is intrinsically interlevel.",
      "Mechanistic decomposition reveals modular structure: the system is scientifically tractable BECAUSE it decomposes into mechanisms.",
      "Anti-covering-law: explanation doesn't require universal laws (deductive-nomological). Phenomena are explained by generative mechanisms even where clean laws are absent.",
      "Dominates explanatory practice in molecular biology, cognitive neuroscience, biochemistry, pharmacology — where 'mechanism' is the natural vocabulary.",
    ],
    formulas: [],
    controversies: [
      "Is 'mechanism' too liberal — does it cover anything organized to produce a phenomenon, including non-mechanistic systems?",
      "How does mechanistic explanation relate to dynamical/mathematical explanation? Are they rivals (Chemero, van Gelder) or complementary?",
      "Does mechanism require localization? Some phenomena (consciousness, perhaps) may not decompose neatly.",
      "Constitutive vs etiological mechanisms (Craver): which kind of 'producing' does a mechanism do?",
    ],
    opposing: [
      { name: "Dynamicism / Dynamical Explanation", who: "van Gelder 1995; Chemero 2009", brief: "In some sciences (esp. dynamical cognitive science) the explanatory unit is a differential equation, not a mechanism. Mechanism asks the wrong question." },
      { name: "Covering-Law / DN Model", who: "Hempel 1948; classical phil sci", brief: "Explanation requires deductive derivation from natural laws. Mechanism is a heuristic; real explanation is logical/nomological." },
      { name: "Functionalism", who: "Putnam, Fodor", brief: "Focus on what a system does (functional role), not how it does it (mechanism). Cognitive science took the functional route for decades." },
      { name: "Inference to the Best Explanation Pluralism", who: "Lipton, Cartwright", brief: "Many kinds of explanation; mechanism is one among many. No need to privilege it." },
    ],
  },

  cr: { label: "Critical Realism", short: "CR", color: C.cr, category: "metaphysical",
    desc: "Bhaskar — stratified ontology: empirical (experienced), actual (events), real (generative mechanisms and powers). Sympathetic to strong emergence; each stratum has irreducible powers. Major influence in social-science methodology. Bridges naturalism with scientific realism.",
    origin: "Bhaskar 1975 'A Realist Theory of Science'; Bhaskar 1979 'The Possibility of Naturalism'",
    thinkers: ["Roy Bhaskar", "Margaret Archer", "Tony Lawson", "Andrew Collier", "Berth Danermark", "Mervyn Hartwig"],
    purpose: "Provides a stratified ontology in which reality has multiple irreducible levels, each with its own generative mechanisms and emergent causal powers. Lets you ask: which stratum is this phenomenon located in? What mechanisms operate here? How do open-system tendencies differ from closed-system regularities? What it adds: the philosophical framework that has worked through emergence, stratification, and multi-level reality more carefully than any alternative — particularly central in social science methodology.",
    principles: [
      "Three-tier stratified ontology: the EMPIRICAL (what's experienced), the ACTUAL (events that occur whether experienced or not), and the REAL (generative mechanisms and powers that produce events).",
      "The real is stratified: each level has emergent powers irreducible to lower levels (Bhaskar's 'ontological depth'). Strongly emergence-friendly.",
      "Generative mechanisms produce events. Experimental science isolates them by 'closing' systems; outside the lab, in 'open systems,' multiple mechanisms interact, producing tendency rather than constant conjunction.",
      "Causal laws describe TENDENCIES of generative mechanisms, not universal regularities. Reconciles real laws with messy observed irregularity.",
      "Naturalism (Bhaskar): no methodological gulf between natural and social science — both seek generative mechanisms — but social systems have distinctive emergent features (rules, meanings, intentionality).",
      "Strong fit with complexity science: open systems, generative mechanisms at multiple levels, emergent powers, are CR's bread and butter.",
    ],
    formulas: [],
    controversies: [
      "Is CR's stratified ontology genuinely distinct from standard layered emergence, or a renaming?",
      "Bhaskar's later 'dialectical critical realism' and 'meta-Reality' phases are widely seen as having lost analytic rigor; many CR-influenced researchers stick with the early work.",
      "How sharp the boundary is between CR and standard scientific realism (or, indeed, between CR and powers ontology).",
      "Whether CR's social-science applications inherit problems specific to social ontology (group agency, meanings, normativity).",
    ],
    opposing: [
      { name: "Empiricist Positivism", who: "Vienna Circle; Carnap, Ayer", brief: "Science is about regular patterns of observable events. Talk of unobservable 'mechanisms' and 'powers' is metaphysical excess." },
      { name: "Constructionist Sociology", who: "Berger & Luckmann; modern social construction", brief: "Social entities are constructions, not 'real' in CR's sense. Especially strong opposition in sociology and STS." },
      { name: "Standard Scientific Realism", who: "Boyd, Psillos", brief: "Doesn't need CR's three-tier machinery — can accept generative mechanisms and emergent properties without the stratified ontology." },
      { name: "Pragmatism", who: "Rorty, putnam (late)", brief: "Realism/anti-realism is a pseudo-debate. What matters is what works for inquiry; CR's metaphysical commitments are unnecessary." },
    ],
  },

  sub: { label: "Substance Metaphysics", short: "SUB", color: C.sub, category: "metaphysical",
    desc: "Lowe, Loux, Tahko — modern Neo-Aristotelianism. Reality consists primarily of substances: independent existents with intrinsic natures (essences). Properties exist in substances; relations are derivative. The most direct ontological rival to Structural Realism.",
    origin: "Aristotle 'Metaphysics' (substance, essence, hylomorphism); modern revival: Lowe 2006 'The Four-Category Ontology'; Loux 2006; Oderberg 2007; Tahko 2015",
    thinkers: ["E.J. Lowe", "Michael Loux", "Tuomas Tahko", "David Oderberg", "Kit Fine (mixed views)", "Anjan Chakravartty", "Jonathan Lowe (four-category)"],
    purpose: "Articulates the traditional and still-defended view that reality consists of substances with intrinsic essences, and relations are derivative on the things they relate. Lets you ask: what is the essential nature of this kind of thing? What makes it the kind of thing it is, independent of its current relations? What it adds: the metaphysical position the productive frameworks usually implicitly DENY — making the alternative visible. Substance metaphysics is still the dominant view in everyday cognition and much of biology (natural kinds, species essences).",
    principles: [
      "Reality consists primarily of substances: independent existents with intrinsic natures. Tables, organisms, particles, planets — each is a substance.",
      "Substances have essences — properties that make them what they are. Essences are real, discoverable, not nominal stipulations.",
      "Properties exist IN substances, not free-floating. Universals are real but require substantial bearers (Aristotelian realism about universals).",
      "Identity is intrinsic: an object's identity is determined by its essential nature, not by its relations. Strong opposition to SR's relational individuation.",
      "Natural kinds carve nature at the joints — they are discoveries, not conventions. Species, elements, biological kinds are real natural kinds.",
      "Modern neo-Aristotelians often combine substance with powers (hybrid view): substances with essential dispositional powers. Most active contemporary substance metaphysics is of this hybrid kind.",
    ],
    formulas: [],
    controversies: [
      "The 'bare particular' problem: what is a substance APART from its properties? If nothing, substance metaphysics threatens to collapse.",
      "Whether quantum mechanics is compatible with substance metaphysics — entanglement, identical particles, no clean individuation challenge the basic ontology.",
      "Whether biology identifies natural kinds in the strong substantialist sense (species concept debates).",
      "Tension with multiple realizability: if essences are intrinsic, MR is hard to accommodate. Modern substance metaphysicians have proposed weaker essentialisms in response.",
    ],
    opposing: [
      { name: "Structural Realism", who: "Ladyman & Ross 2007", brief: "Relations are primary; objects are nothing over and above their relational position. Direct opposition: relations-first vs substances-first." },
      { name: "Process Philosophy", who: "Whitehead, Bergson, Dupré", brief: "Substance is an abstraction from process; only events/processes are fundamental. Substance metaphysics mistakes patterns of becoming for static entities." },
      { name: "Trope Theory", who: "D.C. Williams; Maurin", brief: "There are only particular property-instances (tropes), no underlying substances bearing them. Substance is a redundant addition." },
      { name: "Bundle Theory", who: "Hume, Russell (early)", brief: "Objects are bundles of properties, with nothing 'underneath.' Substance is an unobservable substrate posit." },
      { name: "Mereological Nihilism", who: "van Inwagen 1990; Sider", brief: "There are no composite objects (only simples / organisms). Most putative substances don't exist; substance metaphysics is too generous." },
    ],
  },

  ct:  { label: "Category Theory", short: "CT", color: C.ct, category: "productive",
    desc: "Eilenberg, Mac Lane, Lawvere; modern applied work by Spivak, Fong, Coecke, Baez — pure structural mathematics built from objects-and-morphisms, composition, functors, natural transformations. The most rigorous formalism for 'what is preserved across mappings between systems.' Bridges directly to SR: where SR says relations are primary, CT provides the math. Applications to physics, computation, type theory, compositional systems, network theory, and increasingly to biology and cognition.",
    origin: "Eilenberg & Mac Lane 1945; Lawvere 1960s (Functorial semantics); modern applied: Baez 2000s–, Spivak, Fong & Sobociński 2019 'An Invitation to Applied Category Theory'",
    thinkers: ["Samuel Eilenberg", "Saunders Mac Lane", "F. William Lawvere", "Jean Bénabou", "Bob Coecke (quantum)", "John Baez", "David Spivak", "Brendan Fong", "Pawel Sobociński"],
    purpose: "Provides the most rigorous mathematics of structure-preserving mappings between systems: objects, morphisms, functors, natural transformations — relations made formal. Lets you ask: what's preserved when I translate this system into that one? What's the universal property characterizing this construction? Is this analogy actually structural? What it adds: the formal substrate that lets you compare wildly different systems (quantum protocols, neural networks, biological processes) when they share categorical structure — and the mathematical home of structural realism.",
    principles: [
      "Objects + morphisms (arrows between objects) + composition + identity. That's the entire core. Everything else is structure built on these primitives.",
      "Functors are structure-preserving maps between categories — they encode 'analogy between systems' at the highest level of mathematical rigor.",
      "Natural transformations are maps between functors — capturing 'the same kind of map, applied uniformly.' Mac Lane and Eilenberg introduced categories specifically to define natural transformations.",
      "Universal properties (limits, colimits, adjoints) characterize structures by what they do, not what they are — the most relational possible definition.",
      "Compositional: complex systems built from simple parts whose composition rules are made explicit. Applied CT (string diagrams, monoidal categories) provides graphical calculi for compositional reasoning.",
      "Substrate-free by construction. The same categorical structure (e.g., a monoidal category) describes quantum protocols, neural networks, and chemical reactions identically.",
    ],
    formulas: [
      { f: "C: Ob(C) + Hom(A,B) + ∘ + id_A", label: "A category — minimal data" },
      { f: "g ∘ f : A → C  for f: A→B, g: B→C", label: "Composition" },
      { f: "F: C → D  preserving id and ∘", label: "Functor (structure-preserving map)" },
      { f: "α_A : F(A) → G(A),  natural in A", label: "Natural transformation" },
      { f: "F ⊣ G  iff Hom(F A, B) ≅ Hom(A, G B)", label: "Adjunction" },
      { f: "Universal property: unique morphism up to iso", label: "Limits / colimits" },
    ],
    controversies: [
      "Whether category theory is a 'language' or a 'foundation.' Lawvere argued for the latter (categorical foundations of math); most working mathematicians treat it as a useful organizing language.",
      "Applied category theory's actual empirical purchase — sometimes accused of relabeling existing structure rather than producing new predictions.",
      "Higher category theory (∞-categories) generalizes classical CT but pays in tractability — when do the extra dimensions earn their cost?",
      "Whether CT subsumes set theory and logic, or is parasitic on them. The foundations-of-foundations debate.",
    ],
    opposing: [
      { name: "Set-Theoretic Foundations", who: "ZFC; Cantor → modern set theorists", brief: "Sets and elements are the ground; categories are constructions over sets. CT mistakes a useful abstraction for a foundation." },
      { name: "Type Theory (HoTT)", who: "Martin-Löf; Voevodsky's univalent foundations", brief: "Types as primitive, with computational content. Compatible with CT (∞-toposes) but a distinct foundational stance." },
      { name: "Structural Realism (without CT)", who: "Ladyman & Ross", brief: "SR philosophy without committing to CT specifically. Most SR proponents use CT as a tool but not as essential machinery." },
      { name: "Operational / Algebraic Approaches", who: "Various physics + CS traditions", brief: "Prefer concrete algebras (groups, rings) to abstract categorical generalizations. 'Category theory is generalized abstract nonsense.' (joke originating in the 1970s, now affectionate.)" },
    ],
  },

  cyb: { label: "Cybernetics", short: "CYB", color: C.cyb, category: "productive",
    desc: "Wiener, Ashby, von Foerster, Bateson, Beer — the original transdisciplinary framework for control, communication, and feedback in systems. First-order cybernetics studies regulated systems; second-order cybernetics studies the observer-as-part-of-system (von Foerster). Predates and partially grounds NET, AIF, MEC, and modern complexity science. The 'missing predecessor' often skipped in contemporary teaching but conceptually foundational.",
    origin: "Wiener 1948 'Cybernetics'; Ashby 1956 'Introduction to Cybernetics'; second-order: von Foerster 1970s",
    thinkers: ["Norbert Wiener", "W. Ross Ashby", "Heinz von Foerster", "Gregory Bateson", "Stafford Beer", "Margaret Mead", "Warren McCulloch", "Humberto Maturana"],
    purpose: "Provides the original transdisciplinary vocabulary for control, communication, and feedback in systems — predecessor to modern complexity science. Lets you ask: what's the goal-state, what's being regulated, what's the loop structure, what's the requisite variety the regulator must have? What it adds: Ashby's law of requisite variety and the Conant-Ashby theorem ('every good regulator must be a model'), plus second-order cybernetics' attention to observer-as-part-of-system — load-bearing concepts often forgotten in modern teaching.",
    principles: [
      "A system is regulated when its outputs are compared against a goal-state and the difference drives corrective action. Feedback closes the loop: output → comparison → correction → output. The minimal cybernetic structure.",
      "Requisite variety (Ashby): a regulator must have at least as much variety as the disturbance it must handle. H(R) ≥ H(D). Often the controlling constraint on what can be regulated at all.",
      "Conant-Ashby theorem: every good regulator of a system must be a model of that system. Predictive modeling is constitutive of effective control.",
      "Negative feedback stabilizes (homeostasis, thermostats, biology). Positive feedback amplifies (runaway dynamics, ecological crashes). Net loop polarity determines system behavior.",
      "Second-order cybernetics: the observer is part of the system. Self-reference, autopoiesis (Maturana & Varela), reflexivity in social systems. Bateson: 'the map is not the territory; but the map-maker is part of the territory.'",
      "Cybernetics is substrate-free in principle: the same feedback math applies to thermostats, hormonal systems, social policy, ecosystems, and ML training loops.",
    ],
    formulas: [
      { f: "u(t) = K · (r(t) − y(t))", label: "Basic feedback control law" },
      { f: "H(R) ≥ H(D)", label: "Ashby's law of requisite variety" },
      { f: "Good regulator ⇒ R ≅ model of system", label: "Conant-Ashby theorem" },
      { f: "Loop gain L = ∏ (component gains)", label: "Stability if |L| < 1 in negative loops" },
    ],
    controversies: [
      "Cybernetics as a field largely dissolved in the 1980s, with its insights absorbed into control theory, AI, systems biology, complexity science. Is cybernetics a discipline or a vocabulary?",
      "Whether second-order cybernetics is genuinely empirical or veers toward constructivist philosophy of science with limited testable content.",
      "Application to social systems (Beer's Viable System Model, Project Cybersyn) is celebrated by some, criticized as technocratic by others.",
      "Relationship to systems theory, complexity science, and modern AI safety thinking (Stuart Russell's 'human compatible' AI is a cybernetic framing).",
    ],
    opposing: [
      { name: "Pure Control Theory (modern)", who: "Kalman, Bellman, modern engineering", brief: "Mathematically rigorous successor that absorbed cybernetics' best insights. Some argue control theory is what cybernetics 'should have been' once made formal." },
      { name: "Symbolic AI / Cognitivism", who: "Newell & Simon, early AI", brief: "Mid-20th-century rival framing: cognition as symbol manipulation, not feedback. Largely supplanted by ML but the philosophical divergence is real." },
      { name: "Behaviorism", who: "Skinner; classical behaviorism", brief: "Stimulus-response without internal models. Cybernetics specifically introduces internal goal-states and feedback — explicitly anti-behaviorist." },
      { name: "Embodied / Enactivist Cognition", who: "Varela, Thompson, Di Paolo", brief: "Sees itself as second-order cybernetics' direct heir. Compatible at the core, but rejects the engineering-control framing." },
    ],
  },

  phe: { label: "Phenomenology", short: "PHE", color: C.phe, category: "metaphysical",
    desc: "Husserl, Heidegger, Merleau-Ponty; modern revival in Dan Zahavi, Shaun Gallagher, Evan Thompson — lived experience as primary methodological data, accessible only first-person, prior to and not reducible to natural-scientific description. Bridges to 4E cognition, AIF (in some readings), and the philosophy of mind. The contemporary alternative to fully naturalistic ontology.",
    origin: "Husserl 1900–1913 'Logical Investigations' / 'Ideas'; Heidegger 1927 'Being and Time'; Merleau-Ponty 1945 'Phenomenology of Perception'; modern revival: Zahavi, Gallagher, Thompson 2000s–",
    thinkers: ["Edmund Husserl", "Martin Heidegger", "Maurice Merleau-Ponty", "Edith Stein", "Dan Zahavi", "Shaun Gallagher", "Evan Thompson", "Hubert Dreyfus"],
    purpose: "Provides the disciplined methodology and conceptual vocabulary for taking first-person lived experience as primary data, not derivative of third-person science. Lets you ask: what's the structure of experience itself? How do intentionality, embodiment, temporality, and intersubjectivity constitute the world that science investigates? What it adds: the methodological alternative to fully naturalistic ontology, and the only systematic approach to questions about subjective character that current cognitive science struggles with.",
    principles: [
      "The phenomenological epoché: bracket natural-scientific commitments and describe experience as it presents itself, before theoretical reduction. Method, not metaphysics.",
      "Intentionality: consciousness is always *of* something — a directed structure linking subject and object. The basic structure of experience.",
      "Lived body (Merleau-Ponty): the body is not an object in the world but the medium *through which* a world appears. Cognition is bodily, not separable from sensorimotor existence.",
      "Lifeworld (Husserl's Lebenswelt): the pre-theoretical world of everyday experience that all scientific abstraction presupposes. Science draws on a lifeworld it cannot replace.",
      "First-person methodology: phenomenological investigation requires trained introspective discipline. Not introspection in the loose sense — a structured method.",
      "Anti-Cartesian: rejects the subject/object split as primary. Subject and world co-arise in the structure of experience.",
    ],
    formulas: [],
    controversies: [
      "Whether phenomenological data can be intersubjectively verified, or remains hopelessly private.",
      "The 'naturalizing phenomenology' project (Petitot, Roy, Varela): can phenomenology be reconciled with natural science, or are they categorically separate?",
      "Internal split between transcendental phenomenology (Husserl) and existential phenomenology (Heidegger, Merleau-Ponty).",
      "Whether modern cognitive science's predictive-processing models (AIF) capture phenomenological insights or fundamentally miss them.",
    ],
    opposing: [
      { name: "Eliminative Materialism", who: "Patricia & Paul Churchland", brief: "Phenomenological reports are folk-psychology that future neuroscience will eliminate. Lived experience is illusory at the relevant explanatory level." },
      { name: "Functionalism / Cognitivism", who: "Putnam, Fodor, classical CogSci", brief: "Mind is computation over representations; first-person experience is either reducible to functional role or epiphenomenal." },
      { name: "Analytic Philosophy of Mind", who: "Dennett, Block, Chalmers (mixed)", brief: "Various analytic approaches to mind that engage phenomenology selectively. Dennett: phenomenology is heterophenomenology. Chalmers: phenomenology marks the hard problem." },
      { name: "Direct Realism / Naive Realism", who: "Austin, modern disjunctivists", brief: "We perceive the world directly, not phenomenal representations of it. Phenomenology gets the structure of perception wrong by mediating it through experience." },
    ],
  },

  e4:  { label: "4E Cognition / Enactivism", short: "4E", color: C.e4, category: "metaphysical",
    desc: "Varela, Thompson, Rosch (1991 'The Embodied Mind'); modern: Hutto & Myin (radical enactivism), Di Paolo, Clark (extended mind) — cognition is embodied, embedded, extended, and enacted. Not internal representation but ongoing sensorimotor coupling with environment. The contemporary alternative to representationalist cognitivism and to Friston's AIF in its strong forms. Direct heir to second-order cybernetics + phenomenology.",
    origin: "Varela, Thompson & Rosch 1991 'The Embodied Mind'; Clark & Chalmers 1998 'The Extended Mind'; Hutto & Myin 2013 / 2017 (radical enactivism); Di Paolo, De Jaegher (participatory sense-making)",
    thinkers: ["Francisco Varela", "Evan Thompson", "Eleanor Rosch", "Andy Clark", "David Chalmers", "Daniel Hutto", "Erik Myin", "Ezequiel Di Paolo", "Hanne De Jaegher", "Alva Noë"],
    purpose: "Provides a coherent framework for cognition as embodied, embedded, extended, and enacted — challenging the cognitivist picture of mind as internal representation. Lets you ask: where does this cognitive system actually extend to? What sensorimotor coupling constitutes its engagement with the world? Does this task even require representations? What it adds: the contemporary alternative to representationalism in cognitive science — and a working philosophy of mind that takes biology, body, and environment seriously as constitutive of cognition.",
    principles: [
      "Embodied: cognition is shaped by, and not separable from, the body that does it. Different bodies, different cognitions.",
      "Embedded: cognition uses environmental structure as scaffolding — the brain offloads computation onto the world (notebooks, tools, social practices).",
      "Extended (Clark & Chalmers): when external resources play the same functional role as internal cognition, they are part of the cognitive system. The mind extends past the skull.",
      "Enacted (Varela): cognition is constituted by sensorimotor patterns of engagement with the environment — a 'bringing forth' of a world through embodied action.",
      "Radical enactivism (Hutto & Myin): basic cognition has NO content / NO representations at all. Representational talk applies only to socio-culturally scaffolded higher cognition.",
      "Autopoiesis is the biological foundation (Maturana & Varela): a living system is one that produces and maintains itself. Cognition is the activity of an autopoietic system in its environment.",
      "Anti-representational at the base level. Cognition is a doing, not an internal model — though some 4E versions allow representations as a special case.",
    ],
    formulas: [],
    controversies: [
      "Whether 4E theories can explain offline cognition (planning, memory, imagination) without representations — Hutto & Myin claim yes, critics argue no.",
      "Whether the 'extended mind' thesis is a substantive claim or just a redrawing of cognitive boundaries by stipulation (Adams & Aizawa critique).",
      "Friston's AIF vs enactivism: both claim to capture cognition, but FEP treats organisms as inference machines while enactivism rejects the inference framing. Active debate (Bruineberg, Kiverstein, Rietveld 2016).",
      "How to scale 4E claims from simple sensorimotor cognition to language, science, mathematics.",
    ],
    opposing: [
      { name: "Classical Cognitivism", who: "Fodor, Pylyshyn", brief: "Cognition IS internal representation manipulation. 4E denies the central explanatory move." },
      { name: "Active Inference (FEP)", who: "Friston", brief: "Cognition as variational inference under a generative model — fundamentally representational. Bruineberg-Kiverstein argue FEP can be read enactively, but the standard reading is internalist." },
      { name: "Computational Theory of Mind", who: "Putnam, classic CTM", brief: "Mind is the running of a program. 4E rejects the symbolic-computation framing of cognition." },
      { name: "Predicative AI Models", who: "Most current deep learning research", brief: "Modern ML largely operates on a representational paradigm. Enactivists argue this misses what genuine cognition is." },
    ],
  },

  pcm: { label: "Pancomputationalism / Information Realism", short: "PCM", color: C.pcm, category: "metaphysical",
    desc: "Wheeler 'it from bit'; Wolfram 'A New Kind of Science'; Lloyd 'Programming the Universe'; Tegmark 'Mathematical Universe'; Deutsch & Marletto (constructor theory adjacent). The metaphysical claim that reality is fundamentally informational or computational — physical substrate is derived from information processing, not the other way around. Currently the most ambitious metaphysical companion to IT.",
    origin: "Wheeler 1990 'It from Bit'; Fredkin 1990s digital physics; Wolfram 2002; Lloyd 2006; Tegmark 2014 'Mathematical Universe Hypothesis'",
    thinkers: ["John Archibald Wheeler", "Konrad Zuse (early)", "Edward Fredkin", "Stephen Wolfram", "Seth Lloyd", "Max Tegmark", "David Deutsch", "Chiara Marletto"],
    purpose: "Articulates the metaphysical position that information processing is ontologically fundamental — reality is computation, matter and energy are derivative. Lets you ask: what would it mean to take 'it from bit' seriously? Which physical interpretations are information-theoretic at the foundation (QBism, relational QM)? What it adds: the natural metaphysical companion to information theory — making explicit what's implicit when researchers treat information as more real than substance. Contested but increasingly central to philosophy of physics.",
    principles: [
      "Wheeler: 'It from bit' — every physical 'it' derives its existence from information-theoretic answers to yes/no questions. The universe is observer-participatory.",
      "Pancomputationalism: every physical process IS a computation. The universe is a giant computer; particles are bits being processed.",
      "Digital physics (Fredkin, Wolfram): spacetime is discrete; physical laws are cellular-automaton rules at some fundamental scale.",
      "Mathematical Universe Hypothesis (Tegmark): physical existence and mathematical existence are identical. Every consistent mathematical structure is physically real (multiverse implication).",
      "Information ontology: information is the most fundamental category, more basic than matter, energy, or spacetime. Inverts the standard physicalist hierarchy.",
      "Constructor theory adjacent (Deutsch & Marletto): physics rewritten as facts about which transformations are possible. Information becomes a primitive physical quantity.",
    ],
    formulas: [
      { f: "Reality ≡ information processing", label: "Pancomputationalist thesis" },
      { f: "Universe = computation on bit-level state", label: "Digital physics (Fredkin/Wolfram)" },
      { f: "∀ consistent math structure ⇒ physical", label: "Tegmark MUH" },
    ],
    controversies: [
      "Trivialization worry (Putnam, Searle): if 'everything is a computation' becomes 'every physical system implements every computation,' the thesis is empty. Defenders need a non-trivial implementation criterion.",
      "Empirical content: pancomputationalism makes few directly testable predictions distinct from standard physics. Is it metaphysics dressed in physics vocabulary?",
      "The MUH multiverse: predicts infinitely many parallel structures that we have no way to observe. Falsifiability concerns.",
      "Relationship to constructor theory: are they the same view, or competing? Walker has argued they're complementary; others see them as rivals.",
      "Whether 'information' in 'information realism' is the same concept as Shannon information, or stretched beyond recognition.",
    ],
    opposing: [
      { name: "Materialism / Physicalism", who: "Standard contemporary physicalism", brief: "Matter and energy are basic; information is a way of describing patterns in them, not their substrate. Reverses pancomputationalism's ordering." },
      { name: "Substance Metaphysics", who: "Lowe, Aristotelian tradition", brief: "Information without bearers is incoherent. There must be substantial things doing the computing." },
      { name: "Process Philosophy", who: "Whitehead, Bergson", brief: "Process is more fundamental than information. Information is a derived category — patterns in becoming, not its substrate." },
      { name: "Phenomenology / 4E", who: "Husserl-Merleau-Ponty; Varela", brief: "Experience and embodied engagement are prior to any informational framing. Pancomputationalism is the most extreme form of third-person reduction." },
      { name: "Constructive Empiricism", who: "van Fraassen", brief: "We have no observational warrant for grand claims like 'reality is computational.' This is metaphysical speculation beyond what science establishes." },
    ],
  },

  con: { label: "Constructor Theory", short: "CON", color: C.con, category: "metaphysical",
    desc: "Deutsch & Marletto (2013–) — reformulates physics in terms of which transformations (tasks) are physically possible vs impossible, taking counterfactuals as primary rather than initial conditions and laws of motion. A 'constructor' is anything that performs a task while remaining unchanged; physics becomes facts about possible vs impossible tasks. Programmatic but ambitious — claims to subsume information theory, thermodynamics, and the foundations of life. Bridges to Assembly Theory (Walker has worked at the intersection).",
    origin: "Deutsch 2013 'Constructor theory'; Marletto 2014 'Constructor theory of information'; Marletto 2015 'Constructor theory of life'",
    thinkers: ["David Deutsch", "Chiara Marletto", "Vlatko Vedral (related)", "Sara Walker (assembly theory bridge)"],
    purpose: "Reformulates physics around counterfactuals: which transformations are physically POSSIBLE vs. IMPOSSIBLE, rather than initial conditions plus laws of motion. Lets you ask: what tasks can this system perform? What's the structure of possibility-space, independent of what actually happens? What it adds: a programmatic but ambitious alternative foundation for physics — particularly suggestive for information, life, and computation as physical phenomena. Programmatic stage; mostly conceptual.",
    principles: [
      "Physics expressed via counterfactuals — what tasks ARE and ARE NOT possible — rather than initial conditions plus laws of motion. The fundamental questions concern possibility, not actuality.",
      "A constructor is anything that performs a task on a substrate while remaining unchanged (a catalyst is the prototype; computers, replicators, organisms generalize it).",
      "Information becomes a first-class physical quantity: a system carries information iff the task of copying it is possible. No appeal to observer or to probability distributions.",
      "Counterfactual definiteness: facts about what WOULD happen if X were done are taken as fundamental, not derived from a state-and-laws description.",
      "Life as constructor: living systems are accurate constructors of themselves — the framework reframes the origin-of-life question as 'when do good-enough self-constructors become possible?'",
      "Thermodynamics reframed: the second law as a fact about which heat-transfer tasks are impossible, not about probability or entropy increase per se.",
    ],
    formulas: [
      { f: "Task T: {input → output}", label: "Constructor primitive — a transformation" },
      { f: "T is possible ⇔ ∃ constructor performing T", label: "Definition of physical possibility" },
      { f: "Information: copy-task possible", label: "Information as task-possibility" },
    ],
    controversies: [
      "Whether constructor theory adds anything to standard physics or merely re-expresses it in counterfactual vocabulary. Empirical content remains debated.",
      "Programmatic stage — Deutsch and Marletto have outlined the framework but few researchers outside their group have produced derivations.",
      "Relationship to standard quantum mechanics: complementary or rival? Deutsch claims foundational; critics say redundant.",
      "Whether the 'constructor' notion is well-defined enough to do the foundational work asked of it.",
      "Overlap with Assembly Theory — Walker has worked the bridge but the two frameworks differ on whether counterfactuals or assembly histories are more fundamental.",
    ],
    opposing: [
      { name: "Standard Physics", who: "Mainstream physics community", brief: "Initial conditions + laws of motion are sufficient and well-tested. Counterfactual reformulation is at best convenient, not fundamental." },
      { name: "Pancomputationalism", who: "Wolfram, Lloyd, Tegmark", brief: "Reality is computation, not constructor-action. Computation IS the basic operation; constructors are special-case computational processes." },
      { name: "Assembly Theory", who: "Walker, Cronin", brief: "Closely related but differs: AT tracks construction HISTORIES (assembly paths); CON tracks possibility of tasks. Walker has bridged them; others see them as competitors." },
      { name: "Process Philosophy", who: "Whitehead, Bergson tradition", brief: "Process metaphysics already treats becoming as primary. Constructor theory is mathematical process metaphysics for physics; might be re-inventing the wheel." },
      { name: "Standard Information Theory", who: "Shannon tradition", brief: "IT is the established framework. Marletto's 'constructor theory of information' is contested as either equivalent to standard IT or making implausible reductive claims." },
    ],
  },
};

// ─── FRAMEWORK RELATIONS (for Graph tab) ─────────────────────────────────────
// Each edge has: from, to, type, note. Direction matters for arrowed types.
const FRAMEWORK_RELATIONS = [
  // ANCHORS ↔ ANCHORS
  { from: "sr", to: "it", type: "uses",
    note: "SR uses IT's quantitative tools (real-pattern criterion is compressibility).",
    detail: "Structural Realism inherits its operational criterion from Information Theory. Ladyman & Ross (2007, 'Every Thing Must Go') argue what exists are 'real patterns' — and take Dennett's compressibility criterion (a pattern is real iff describing data via the pattern is shorter than describing the data raw) as the operational test. This is an information-theoretic claim: K(data) > K(pattern) + K(data | pattern). Without IT, SR has no way to distinguish real patterns from ad hoc descriptions. IT supplies the mathematics SR needs to be more than a philosophical slogan." },

  // ANCHORS → PRODUCTIVE
  { from: "sr", to: "net", type: "uses",
    note: "Networks ARE structural realism made explicit — graphs are relational structure.",
    detail: "A graph (V, E) is literally a set of relations between objects with no object-level content beyond what the edges specify. If SR's claim is that 'what exists is relational structure,' a network IS that structure made mathematically explicit. Network science gives SR its most concrete realization: degree distributions, centrality, community structure, spectral properties — all are descriptions of pure relational form, with the nodes serving only as relata. SR practitioners often treat networks as the canonical concrete example when defending the view." },

  { from: "sr", to: "cm", type: "compatible",
    note: "ε-machines are objectively privileged real patterns in SR's sense.",
    detail: "Crutchfield's ε-machines satisfy SR's strongest desideratum: they are objectively privileged structural representations of a process, unique up to isomorphism, discovered rather than chosen. The causal states emerge from an equivalence relation on histories (h ~ h' iff P(future | h) = P(future | h')) — a structural definition that doesn't depend on observer preferences. For SR this is the ideal case: a real pattern whose status as real isn't observer-dependent. Crutchfield himself has written about computational mechanics as a mathematics of structural realism." },

  { from: "sr", to: "ce", type: "compatible",
    note: "Real patterns at causally-privileged scales (Rainforest Realism).",
    detail: "Hoel's causal emergence says some coarse-grainings have strictly more causal information (higher EI) than the underlying micro level. Ladyman & Ross's 'Rainforest Realism' is the natural philosophical home: reality has many real levels, each potentially with its own causal structure. CE provides empirical machinery for identifying which levels are causally real — exactly what SR-Rainforest needs to move beyond gestures toward 'multi-level reality.' The compatibility is methodological: SR provides the ontology, CE provides the computable test." },

  { from: "sr", to: "ait", type: "compatible",
    note: "Algorithmic real-pattern criterion — Dennett + Kolmogorov.",
    detail: "Dennett's original real-pattern criterion was implicitly Shannon-flavored (compressibility relative to a noisy channel). AIT sharpens it to individual objects: pattern P is real with respect to data d iff K(d) > K(P) + K(d | P). This gives SR an algorithmic real-pattern criterion that works for individual objects, not just ensembles — answering a major objection to Dennett's original formulation. The two anchor on the same compressibility intuition; AIT just makes it work where Shannon couldn't." },

  { from: "it", to: "ait", type: "extends",
    note: "AIT extends Shannon IT from ensembles to individual objects.",
    detail: "Shannon entropy H(X) = E[-log p(x)] is defined over a probability distribution — it characterizes ensembles, not individuals. Kolmogorov complexity K(x) is the length of the shortest program producing x on a universal Turing machine. The link: E_p[K(x)] ≈ H(p) + O(K(p)) for computable distributions. AIT generalizes Shannon to single objects, drops the requirement for a known distribution, and links information directly to computation. The cost is uncomputability of K — but most operational use cases substitute compression-based approximations." },

  { from: "it", to: "cm", type: "uses",
    note: "CM uses entropy rate, excess entropy, statistical complexity.",
    detail: "Computational Mechanics is built directly on Shannon IT. The entropy rate h_μ = lim_n H(X_n | X_{n-1}, ..., X_1) measures process randomness. Excess entropy E = I(past; future) measures predictability. Statistical complexity Cμ = H(causal states) measures the structural complexity of the minimal-sufficient predictor. All three are IT quantities computed over the process's stochastic structure — without IT, CM has no machinery. Crutchfield's program is essentially 'Shannon IT applied to dynamical processes to extract minimal predictive structure.'" },

  { from: "it", to: "ci", type: "uses",
    note: "CI uses mutual information, conditional MI, screening-off.",
    detail: "Pearl's causal inference uses IT throughout: conditional independence (the d-separation criterion) is operationalized via vanishing conditional MI: I(X; Y | Z) = 0. The faithfulness assumption — that all conditional independences in the data reflect graph structure — is an IT-grounded statistical claim. Information-theoretic causal discovery (PC algorithm, FCI, GES) uses conditional independence tests built from MI estimators. Pearl's framework would not be implementable without IT-based independence-testing infrastructure." },

  { from: "it", to: "ce", type: "uses",
    note: "Effective information is IT-based; CE is information-theoretic.",
    detail: "Hoel's effective information EI = I(I_D ; E_D) is mutual information between an intervention distribution and an effect distribution. The intervention prior I_D is typically uniform over states (maximum entropy). CE detection — finding a coarse-graining π such that EI(π(X)) > EI(X) — uses Shannon mutual information directly throughout. Without IT, the framework can't even state its central quantity. The reverse dependency holds too: CE shows that mutual information at the right scale captures causal structure better than at the wrong scale, sharpening IT's interpretive content." },

  { from: "it", to: "aif", type: "uses",
    note: "Variational free energy is a KL divergence (information quantity).",
    detail: "Friston's variational free energy F[q] = D_KL(q ‖ p_posterior) − log p(o) is composed entirely of IT quantities: a KL divergence (relative entropy) and a log-evidence term (negative surprisal). Active inference's perception step minimizes F over q (recognition); its action step minimizes F over policy (control). Both reduce to information-theoretic optimization. The free-energy framework is impossible without IT's KL divergence as its central tool — though, crucially, this F is NOT thermodynamic free energy (see the aif↔th tension)." },

  { from: "it", to: "th", type: "uses",
    note: "Landauer's principle bridges thermodynamic and Shannon entropy.",
    detail: "Landauer (1961) showed erasing one bit of information costs at least k_B T ln 2 in dissipated heat — bridging Shannon entropy (bits) and thermodynamic entropy (joules per kelvin) via a physical constant. Stochastic thermodynamics formalized this: Jarzynski equality and Crooks fluctuation theorem write thermodynamic quantities as ensemble averages over stochastic trajectories, with entropy production directly relating to KL divergences between forward and reverse trajectories. The two were unified in the 2000s-2010s; modern stochastic thermodynamics IS thermodynamic information theory." },

  { from: "it", to: "net", type: "uses",
    note: "Network information measures, spreading dynamics, info-flow on graphs.",
    detail: "Networks use IT for: (i) characterizing edge weights as channel capacities, (ii) measuring node centrality via information-theoretic centrality measures (e.g., entropy centrality), (iii) modeling spreading processes (information diffusion, epidemics) as flows of mutual information across the graph, (iv) defining network entropy and complexity. The interface goes both ways: NET supplies the graph structure, IT supplies the quantities computed over it. Modern network neuroscience and computational sociology rely on this combination heavily." },

  { from: "it", to: "at", type: "uses",
    note: "Assembly index uses information-theoretic concepts of compression.",
    detail: "Assembly theory's central quantity, the assembly index A(x), is the minimum number of joining operations required to construct x from primitives, allowing reuse of intermediate parts. This is closely related to a description-length measure: A(x) ≈ log of the size of the smallest 'construction grammar' generating x. Walker & Cronin (Nature 2023) explicitly draw the parallel to Kolmogorov complexity, though they argue AT differs in measuring physical assembly rather than computational compression. The dependency on IT-style compression intuitions is real even where the authors emphasize the differences." },

  { from: "it", to: "evo", type: "uses",
    note: "Price equation, Fisher information, mutation rate as entropy source.",
    detail: "Evolutionary dynamics uses IT for: (i) Fisher information in population genetics (the Fisher information metric on probability simplexes appears in replicator dynamics), (ii) the Price equation can be cast in information-theoretic form (Frank 2012), (iii) mutation rates as entropy sources injecting variation, (iv) Adami's information-theoretic approach to biological complexity (genome content as Shannon information). Modern phylogenetics, evolutionary game theory, and population genetics all use IT machinery extensively." },

  // ANCHORS ↔ METAPHYSICAL
  { from: "sr", to: "sub", type: "opposes",
    note: "Direct rivals: relations primary (SR) vs intrinsic essences primary (SUB).",
    detail: "The sharpest direct rivalry in contemporary metaphysics. SR claims that objects have no intrinsic natures over and above their positions in relational structure — 'no objects without structure.' Neo-Aristotelian substance metaphysics (Lowe, Loux, Tahko) claims the opposite: substances have intrinsic essences that ground their identity and causal powers, and relations are derivative on the substances they relate. The disagreement is genuine, not verbal: it changes what kind of scientific evidence counts (quantum entanglement is SR-friendly, biological natural kinds are SUB-friendly), and which metaphysical questions count as legitimate. Each accuses the other of presupposing what it should explain." },

  { from: "sr", to: "pow", type: "tension",
    note: "Relations-first (SR) vs intrinsic dispositions (POW). Real tension.",
    detail: "Powers metaphysics (Bird's dispositional essentialism, Mumford & Anjum) claims properties ARE causal powers — what an electron IS is exhausted by what it does (attract, repel, etc.). This is closer to SR than to substance metaphysics: powers are individuated by their relational effects, not by intrinsic essences. But SR goes further: it eliminates the BEARER of powers, treating dispositions themselves as nodes in relational structure. POW retains the idea that something has the power, which SR treats as ontologically unnecessary. The tension shows up most sharply over: do laws of nature describe pre-existing powers (POW) or just the abstract structure of how things relate (SR)?" },

  { from: "sr", to: "pro", type: "compatible",
    note: "Both anti-substance; process is naturally relational.",
    detail: "SR and process philosophy share a foundational commitment: substance is not ontologically primary. Where they differ: SR makes RELATIONS primary; process philosophy makes EVENTS / BECOMINGS primary. But Whitehead's 'societies of actual occasions' are constituted by their relations (prehensions) to other occasions — so process metaphysics is naturally relational. Modern process biology (Dupré, Nicholson) treats organisms as longitudinally relational process patterns, which fits SR's framework comfortably. The compatibility is structural: both reject substantial bearers, both make 'how things hang together' more fundamental than 'what things are.'" },

  { from: "sr", to: "cr", type: "compatible",
    note: "Both committed to multi-level real patterns / generative mechanisms.",
    detail: "Bhaskar's Critical Realism and Ladyman & Ross's Rainforest Realism are independent traditions reaching similar conclusions: reality is stratified, each level has its own irreducible structure, and scientific realism applies to higher levels too. CR's 'generative mechanisms' map onto SR's 'real patterns at multiple scales.' Both views allow strong emergence (CR explicitly, SR-Rainforest implicitly). The traditions developed in parallel without much cross-pollination, but a modern integration would be straightforward: CR provides the stratification ontology, SR-Rainforest provides the patterns-and-relations machinery." },

  { from: "it", to: "sub", type: "tension",
    note: "Information realism vs substance realism — different ontological grounds.",
    detail: "IT as a tool is metaphysically neutral, but information-theoretic interpretations of reality (Wheeler's 'it from bit', Wolfram's computational physics) are deeply opposed to substance metaphysics. Substance metaphysics says: there must be substantial bearers for information; pure information without bearers is incoherent. Information realism says: substance is derivative of information processing, not the other way around. The disagreement runs deep into philosophy of physics: whether quantum mechanics tells us about substantial particles (SUB) or about informational structures (IT-friendly interpretations like QBism). Working scientists rarely choose explicitly, but the choice constrains what you can say about foundations." },

  // PRODUCTIVE ↔ PRODUCTIVE
  { from: "pc", to: "cm", type: "uses",
    note: "CM operates over dynamical processes; uses PC's state-space machinery.",
    detail: "Computational Mechanics analyzes dynamical processes — its causal states partition histories of a stochastic dynamical system. It inherits PC's state-space formulation, time evolution, and ergodic-theoretic foundations. CM's central question — 'what's the minimal predictive representation of this process?' — only makes sense for systems with a well-defined state space and dynamics. Without PC, CM has no subject matter. The reverse: CM extends PC by providing the unique minimal-sufficient predictor of any stationary stochastic process, which is a genuinely new contribution PC didn't have." },

  { from: "pc", to: "th", type: "extends",
    note: "TH extends classical / nonequilibrium PC with fluctuation theorems.",
    detail: "Stochastic thermodynamics took the dynamical systems framework — small systems with stochastic noise, Langevin equations, master equations — and proved exact results (Jarzynski 1997, Crooks 1999) about heat, work, and entropy production that hold arbitrarily far from equilibrium. These fluctuation theorems are derived USING dynamical systems machinery (path integrals over trajectories, time-reversal symmetries) and EXTEND classical thermodynamics by quantifying fluctuations rather than just averages. TH is what PC becomes when you take stochastic noise and dissipation seriously at the microscale." },

  { from: "pc", to: "ce", type: "uses",
    note: "CE computes EI over transition matrices — PC's dynamical apparatus.",
    detail: "Hoel's causal emergence is computed on Markov transition matrices — exactly the discrete-time dynamical-systems representation that PC formalizes. EI(π(X)) compares the macro-scale transition matrix induced by coarse-graining π against the micro transition matrix. The framework is implementable on any system with a discrete state space and transition probabilities — which means PC's dynamical-systems setup is the natural input format. Without dynamical-systems infrastructure (state spaces, transition operators, ergodic measures), CE has nothing to compute on." },

  { from: "pc", to: "evo", type: "uses",
    note: "Replicator equation and evolutionary game dynamics are PC machinery.",
    detail: "Evolutionary dynamics uses ODE machinery from PC throughout: the replicator equation ẋ_i = x_i(f_i − ⟨f⟩) is a continuous-time dynamical system on the probability simplex. Evolutionary game theory analyses fixed points, stability, limit cycles, basin structure — all PC tools. Adaptive dynamics extends this to slow-fast systems. Lotka-Volterra ecological dynamics, niche-construction models, host-parasite coevolution — all formalized as PC systems. EVO without PC would be conceptual without quantitative; PC supplies the math that turns Lewontin's three conditions into predictive theory." },

  { from: "pc", to: "aif", type: "uses",
    note: "AIF uses gradient flow / dynamical systems for inference dynamics.",
    detail: "Active inference dynamics — both Bayesian belief updating and policy selection — are formulated as gradient flows on free-energy landscapes, which are dynamical systems in the PC sense. The perception equation ∂_t μ = -∂_μ F[q] is a gradient descent; action selection involves gradient flow over expected free energy in policy space. Friston's mathematical apparatus (path integrals, generalized coordinates) is direct PC machinery. Without dynamical systems theory, AIF's quantitative formulation collapses to schematic statements about Bayesian agents." },

  { from: "ci", to: "ce", type: "extends",
    note: "Hoel extends Pearl's interventionism to multi-scale causal analysis.",
    detail: "Pearl's do-calculus operates at a single scale: an SCM has its variables, and intervention do(X=x) is defined on those variables. Hoel's CE generalizes this to ask: which scale do you intervene at? It defines EI at any scale (any coarse-graining of the micro-SCM) and asks which scale maximizes effective information. The extension is conceptual (scale becomes a degree of freedom) and technical (you compute EI over the induced macro transition matrix). Pearl's machinery is preserved at each scale; CE adds the scale-selection step. Critics (Eberhardt, Lee 2017) argue the macro EI advantage is partly an artifact of the uniform intervention prior — the extension is real but the philosophical interpretation contested." },

  { from: "cm", to: "ce", type: "compatible",
    note: "Both seek the right scale; CM optimizes prediction, CE optimizes causal power.",
    detail: "CM and CE are kin: both ask 'what's the right level of description?' but optimize different things. CM finds the minimal sufficient predictor — the partition that maximally compresses while preserving prediction (minimizes Cμ subject to preserving E). CE finds the level where intervention is maximally informative (maximizes EI). Where they coincide — which is often, empirically — you have strong evidence for a real privileged level. Where they diverge, you've identified a system where prediction and intervention come apart, which is itself diagnostically valuable. Both reject ad hoc coarse-graining in favor of dynamics-selected scale identification." },

  { from: "cm", to: "ait", type: "compatible",
    note: "Both seek minimality — Cμ relates to K(generative model) for computable processes.",
    detail: "For computable stationary processes, Crutchfield's statistical complexity Cμ (entropy of the causal-state distribution) is closely related to K(generative model) — Kolmogorov complexity of the minimal program generating the process. CM provides a computable approximation to algorithmic minimality for stochastic processes; AIT provides the uncomputable but theoretically clean version. The pair complements each other: AIT is the gold standard, CM is what you can actually compute. Both share the minimal-description philosophy: a process's complexity is the length of its shortest sufficient representation." },

  { from: "ait", to: "at", type: "tension",
    note: "Critics argue AT recapitulates Kolmogorov complexity / logical depth.",
    detail: "When Assembly Theory was first proposed, critics (Adams, Lloyd, others) argued that assembly index A(x) is essentially a restricted form of Kolmogorov complexity, or specifically Bennett's logical depth. The critique: any 'history of construction' measure is reducible to a compression-based measure with appropriate primitives. Walker & Cronin push back: assembly index measures PHYSICAL construction with specific operations (joining and reuse), constrained by what real chemistry can do, not arbitrary computational compression. The tension is unresolved. Both sides agree on the math at the boundary; they disagree on whether AT carves nature at a different joint than AIT does." },

  { from: "evo", to: "at", type: "compatible",
    note: "Assembly index × copy number proposed as a selection signature.",
    detail: "AT's central biological claim: in non-selective chemistry, high-A objects exist only in low copy number (combinatorial space is too large); in selective chemistry (life, technology), high-A objects achieve high copy number through directed assembly. The product A × N is proposed as a substrate-independent signature of selection — distinguishing biology from background chemistry. This makes AT directly compatible with EVO, since selection is what AT claims to detect. The bridge is empirical: A × N rises in evolving systems, plateau in non-evolving ones. Critics question how well the empirical claim holds; the conceptual compatibility is robust." },

  { from: "aif", to: "th", type: "tension",
    note: "Friston's variational free energy ≠ thermodynamic free energy. Frequently conflated.",
    detail: "Friston's variational free energy F[q] = D_KL(q ‖ p_posterior) − log p(o) is an INFORMATION quantity (units: bits or nats). Thermodynamic free energy F = U − TS is a PHYSICAL quantity (units: joules). They share the Helmholtz formal structure (a 'free' part minus a 'bound' part), and there's a deep formal analogy via Boltzmann's connection between entropy and probability. But they are NOT the same object: minimizing variational F doesn't minimize physical heat dissipation. Pop accounts of FEP routinely conflate them ('the brain minimizes free energy — that's why thinking is metabolically expensive!'), producing confusion. The tension is real and persistently miscommunicated." },

  { from: "aif", to: "evo", type: "compatible",
    note: "Agents as evolved Bayesian inference machines; FEP at the lineage level.",
    detail: "Evolutionary biology and active inference have a natural meeting point: an evolved organism is plausibly a Bayesian inference machine, with its generative model tuned by selection to match its ecological niche. Friston has proposed scaling FEP to the lineage level — a lineage that persists minimizes 'evolutionary surprise,' i.e., deviation from viable phenotype distributions. Compatible at the conceptual level (both involve adaptation to a target distribution), though the math of selection (replicator dynamics) and the math of inference (variational Bayes) operate on different timescales and via different mechanisms." },

  { from: "net", to: "evo", type: "compatible",
    note: "Network selection, contact-structure-driven evolution; network science integrates EVO.",
    detail: "Network science and evolutionary dynamics interact richly: (i) evolutionary graph theory (Lieberman, Hauert, Nowak 2005) shows network topology determines fixation probability of beneficial mutants, (ii) epidemic models on networks generalize SIR to graph-structured contact, (iii) cooperation evolves differently on different network topologies (Ohtsuki et al. 2006), (iv) coevolution of network structure and node states (adaptive networks) captures social-ecological systems. The two frameworks are technical complements: NET supplies the topological substrate, EVO supplies the dynamics on it. Most modern social-evolutionary modeling uses both." },

  // METAPHYSICAL → PRODUCTIVE (grounds)
  { from: "pow", to: "ci", type: "grounds",
    note: "Causation as power-manifestation provides ontology for Pearl's SCMs.",
    detail: "Pearl's SCMs describe causation via interventional distributions but are metaphysically thin: they tell you P(Y | do(X)) without saying what causation IS. Powers metaphysics provides the ontology: causation IS the manifestation of dispositional powers under triggering conditions. An SCM edge X → Y, on the Powers reading, represents X's power to produce Y under appropriate conditions. This grounding doesn't change Pearl's math but provides metaphysical foundations: causation isn't just statistical regularity (Hume), it's the operation of real causal powers in the world. Mumford & Anjum (2011) work out this view explicitly." },

  { from: "pow", to: "pc", type: "grounds",
    note: "Attractor basins ARE dispositional structures — what the system WOULD do.",
    detail: "An attractor basin describes what a dynamical system WOULD do under perturbations within the basin — a counterfactual structure. This is precisely a dispositional structure in the Powers sense: the system has a disposition to flow toward the attractor, manifesting whenever perturbed within the basin. Mumford & Anjum's metaphysics naturally accommodates dynamical systems: the state space is a map of system-dispositions, the flow is power-manifestation, bifurcations are changes in disposition-structure. PC supplies the math; POW supplies the ontology of what those equations are equations of." },

  { from: "pow", to: "evo", type: "grounds",
    note: "Selection as the manifestation of differential reproductive powers.",
    detail: "Natural selection requires variation, heritability, and differential fitness. Powers metaphysics naturalizes the third: differential fitness is the manifestation of differential REPRODUCTIVE POWERS — some variants have stronger dispositions to leave descendants under given conditions. This grounds the selection process in the dispositional structure of organisms, rather than treating fitness as a bare statistical regularity. Provides ontology for what's happening 'beneath' the population-level statistics: organisms are bearers of reproductive powers; selection is power-manifestation differentially across variants." },

  { from: "pow", to: "aif", type: "grounds",
    note: "Agency as the manifestation of organized dispositional powers.",
    detail: "Active inference describes agents as Markov-blanketed systems minimizing free energy. Powers metaphysics provides the ontology: an agent IS an organized constellation of dispositional powers — perceptual powers (to update beliefs given sensory input), epistemic powers (to model the environment), action powers (to modify states). The capacity for agency is itself a high-level disposition emerging from organized lower-level dispositions. Friston's math describes the functional structure; Powers describes what the system metaphysically is. Important: this is a friendly grounding, not a critique — most active-inference theorists are not hostile to powers ontology." },

  { from: "pro", to: "pc", type: "grounds",
    note: "Process ontology — becoming as primary, dynamics as the structure of process.",
    detail: "Dynamical systems theory describes how systems CHANGE over time. Process philosophy makes this metaphysically primary: what's real is becoming, not states between which things move. PC's state-space framework is naturally process-friendly when read this way: trajectories are sequences of process-events; attractors are stable process-patterns; bifurcations are qualitative shifts in process structure. Whitehead's 'actual occasions' are the metaphysical analogue of PC's instantaneous states-as-events. The grounding lets process philosophy speak with PC's quantitative voice — and lets PC have a metaphysics that doesn't require static substances." },

  { from: "pro", to: "th", type: "grounds",
    note: "Dissipative structures ARE process patterns; TH is process metaphysics made rigorous.",
    detail: "Prigogine's dissipative structures (Bénard convection, Belousov-Zhabotinsky reactions, biological metabolism) are pattern-MAINTAINING flows, not static things. They exist only as long as energy throughput continues; remove the gradient and they dissolve. This is process philosophy made rigorous: 'the entity' is the stabilized flow-pattern, not any underlying substance. Modern stochastic thermodynamics quantifies the entropy production keeping such structures alive. Process metaphysics has long claimed organisms are flows-of-pattern; TH provides the math, especially via Schrödinger's 'What is Life' insight (organisms feed on negative entropy) updated to modern non-equilibrium thermodynamics." },

  { from: "pro", to: "evo", type: "grounds",
    note: "Lineages as longitudinal process patterns; modern process biology (Dupré, Nicholson).",
    detail: "Modern process biology (Dupré 2012, Nicholson & Dupré 2018 'Everything Flows') applies process metaphysics to biology directly: organisms are not things but stabilized metabolic processes; lineages are longitudinal patterns across generations; species are process patterns at the population scale. This reframes evolution: rather than 'descent with modification of substances,' evolution is the genealogy of process patterns. The reframing has empirical consequences (e.g., re-thinking species concepts, organism boundaries) and methodological ones (treating biology as fundamentally dynamical rather than structural). Process biology is genuinely active in current journals." },

  { from: "pro", to: "aif", type: "grounds",
    note: "Autopoiesis as process self-maintenance — direct application.",
    detail: "Maturana & Varela's autopoiesis (a system continuously producing its own components through its own operations) is the canonical process-metaphysical account of living systems. Active inference, in its strong reading, treats organisms as autopoietic — they minimize free energy AS A MEANS to maintain their characteristic states (their Markov blanket). The grounding: autopoiesis (process self-production) provides the metaphysics of what an FEP-minimizing system is. Note this also connects to the e4↔aif tension: enactivism reads autopoiesis as primary and FEP as derivative; standard AIF reads inference as primary and autopoiesis as one consequence." },

  { from: "mec", to: "ci", type: "grounds",
    note: "Causation IS productive mechanism; mechanistic explanation IS causal explanation.",
    detail: "New Mechanism (Machamer, Darden, Craver, Bechtel) defines causation as productive mechanism: X causes Y means X is part of a mechanism that produces Y. This grounds Pearl's interventional account: the reason intervention on X changes Y's distribution is that X is part of the causal mechanism for Y. Mechanistic explanation IS causal explanation — they're not two methods but the same explanation viewed from different angles. The grounding gives CI a positive metaphysics: causal arrows in SCMs aren't just statistical, they correspond to entities-and-activities producing the phenomena. Working biology and neuroscience implicitly use this view." },

  { from: "mec", to: "evo", type: "grounds",
    note: "Evolutionary mechanisms (selection, drift, mutation) explain biological phenomena.",
    detail: "The MEC view is the dominant philosophy of explanation in molecular biology. Evolutionary explanations exemplify it: a trait's existence is explained by the mechanisms that produced it — random mutation (entities: alleles; activities: random change), differential reproduction (entities: organisms; activities: survival and breeding), drift, gene flow. Each evolutionary mechanism decomposes into entities and activities organized to produce the population-level outcome. Mayr's 'proximate vs ultimate' causes maps onto mechanistic decomposition at different levels. Working evolutionary biology talks in MEC terms even when it doesn't name the framework." },

  { from: "mec", to: "ce", type: "grounds",
    note: "Mechanistic emergence — multi-level mechanisms produce emergent phenomena.",
    detail: "Causal emergence (Hoel) detects causally privileged levels; MEC explains WHY those levels exist: each level is constituted by a mechanism whose components are mechanisms at the lower level (Craver's nested mechanisms). Mechanistic emergence: the phenomenon at level n is produced by the organized activities of components at level n-1, with new causal properties at the higher level. CE is empirically diagnostic; MEC is the explanatory grounding. The pair forms the dominant approach in modern systems biology and cognitive neuroscience: identify the causally privileged level (CE), then unpack its mechanism (MEC)." },

  { from: "cr", to: "ce", type: "grounds",
    note: "Stratified ontology naturally accommodates emergent causal powers per stratum.",
    detail: "Bhaskar's Critical Realism is the metaphysical framework most explicitly committed to strong emergence: each stratum (physical → chemical → biological → psychological → social) has its own emergent causal powers irreducible to lower strata. CE's empirical finding that some scales have causally privileged status fits CR's ontology naturally: those scales correspond to Bhaskar's strata, and the higher-than-baseline EI at those scales reflects the emergent causal powers CR posits. CE is computable from data; CR provides the philosophical framework that makes the result ontologically significant rather than just instrumentally useful." },

  { from: "cr", to: "aif", type: "grounds",
    note: "Generative mechanisms producing observable phenomena; CR is FEP-friendly.",
    detail: "Bhaskar's central distinction — between the EMPIRICAL (what's observed), the ACTUAL (events that occur), and the REAL (generative mechanisms producing them) — fits active inference's generative-model framework. A generative model in AIF represents the real (unobserved) causes producing observed sensory states; inference is the process by which the agent estimates these causes. CR provides the meta-ontology: there really ARE generative mechanisms in the world, and AIF describes how agents come to know them. CR is sympathetic to the explanatory program of AIF without being committed to its specific mathematical machinery." },

  { from: "cr", to: "evo", type: "grounds",
    note: "Open-system biology; evolutionary mechanisms operating in tessellating contexts.",
    detail: "Bhaskar distinguishes closed systems (experimental isolation, single mechanism dominant) from open systems (multiple mechanisms operating simultaneously, producing tendencies not regularities). Most biology is open-system: an organism's fate reflects the interaction of selection, drift, development, ecology, history. CR provides the philosophy of science for this: evolutionary mechanisms are real (generative), but their interaction in open systems produces tendencies rather than strict laws. This grounds why evolutionary biology can't be reduced to clean covering laws — and why that's OK rather than a failure of the science." },

  { from: "sub", to: "evo", type: "tension",
    note: "Species-as-substances debate: are species natural kinds with essences, or lineages?",
    detail: "Aristotelian substance metaphysics treats species as natural kinds with essences: 'human,' 'oak tree,' 'gold' pick out kinds with intrinsic natures. Modern evolutionary biology treats species as lineages — historically connected populations, defined by descent rather than essence. The tension is direct: if species are lineages, they have no Aristotelian essence; if species have essences, they're not lineages in the evolutionary sense. Modern neo-Aristotelians (Devitt, Boyd's homeostatic property cluster view) try to thread the needle with weakened essentialism. The debate is genuine philosophy of biology, not just terminology." },

  // METAPHYSICAL ↔ METAPHYSICAL
  { from: "sub", to: "pro", type: "opposes",
    note: "Direct rivals: substance ontology vs process ontology.",
    detail: "The cleanest metaphysical opposition in the atlas. Substance metaphysics: reality consists fundamentally of substances (things with intrinsic natures); processes are what substances do. Process philosophy: reality consists fundamentally of processes (events of becoming); substances are abstractions from stable process patterns. Each side accuses the other of presupposing its own ontology while denying it. The opposition has practical stakes: organism identity (substance or process?), personal identity (a self or a stream of experience?), institutional identity (an organization or its ongoing activity?). Different scientific questions favor different sides — process biology favors PRO, taxonomy favors SUB." },

  { from: "sub", to: "pow", type: "compatible",
    note: "Neo-Aristotelian hybrid: substances with essential dispositional powers.",
    detail: "Most contemporary substance metaphysicians ARE also powers theorists (Oderberg, Lowe, modern neo-Aristotelians). The hybrid view: substances have intrinsic essences which include essential dispositional powers. Water's essence includes the power to dissolve salt; copper's essence includes electrical conductivity. This hybrid is natural — pure substance metaphysics needs an account of causation, and pure powers metaphysics needs an account of what bears the powers. The combination is robust and currently dominant in Aristotelian-tradition metaphysics. Pure powers without substances (Bird's strong dispositional essentialism) and pure substances without dispositional powers (categorical-base views) are the minority positions." },

  { from: "pow", to: "pro", type: "tension",
    note: "Powers presuppose bearers; process philosophy denies the bearer/substance distinction.",
    detail: "Powers metaphysics says: there are properties (powers) that things have. Process philosophy says: there are no things, only processes — what we call 'things' are stable process patterns. The tension: powers presuppose bearers (something that HAS the power); process philosophy denies primitive bearers. The tension can be relaxed (a 'process having a power' could be reformulated as 'a process with characteristic dispositional structure'), but the metaphysical priority differs. POW takes properties of bearers as primary; PRO takes process itself as primary, with property-like talk derivative. Modern compatibilists try to dissolve this; orthodox theorists keep it." },

  { from: "cr", to: "pow", type: "compatible",
    note: "Bhaskar uses dispositional powers as the ontology of generative mechanisms.",
    detail: "Bhaskar's 'generative mechanisms' that constitute the REAL (in CR's three-tier ontology) are essentially dispositional powers — what entities WOULD do under appropriate conditions. CR and POW are largely complementary: CR provides the stratified ontology (powers operate at each of physical, biological, social strata); POW provides the metaphysics of what those mechanisms are (dispositional powers of stratum-specific entities). Bhaskar himself sometimes used the vocabulary of tendencies and powers interchangeably. Modern CR-influenced researchers (Lawson in economics, Archer in sociology) often use powers metaphysics explicitly." },

  { from: "cr", to: "mec", type: "compatible",
    note: "Generative mechanisms ≈ MEC's entities-and-activities — closely aligned.",
    detail: "Both Critical Realism (Bhaskar) and New Mechanism (Machamer-Darden-Craver) put MECHANISMS at the center of explanation. Bhaskar's 'generative mechanisms' and MEC's 'entities + activities organized to produce phenomena' are nearly the same concept under different vocabulary. Differences: CR emphasizes the stratified/multi-level nature of mechanisms more strongly; MEC has more developed criteria for what counts as a mechanism (componential decomposition, productive continuity). The two could be productively integrated; mostly they've developed in parallel disciplinary contexts (CR in philosophy of social science, MEC in philosophy of biology and neuroscience)." },

  { from: "cr", to: "pro", type: "compatible",
    note: "Stratified processes; CR is broadly process-friendly.",
    detail: "Critical Realism's stratified ontology is naturally process-friendly — each stratum can be understood as a level of ongoing processes (physical processes, biological processes, social processes). Bhaskar's generative mechanisms are typically processual rather than static. CR doesn't require process metaphysics, but the two can be combined: a 'process critical realism' would treat each Bhaskarian stratum as a domain of characteristic processes with emergent properties. The combination is uncommon in published work but conceptually robust. Both reject reductive physicalism and both take higher-level emergent reality seriously." },

  { from: "mec", to: "pow", type: "compatible",
    note: "Mechanisms are organized arrangements of powers; activities ARE power-manifestations.",
    detail: "MEC defines mechanisms as 'entities + activities organized to produce phenomena.' Powers metaphysics naturally interprets the 'activities' as power-manifestations: an entity has powers, and the activities are those powers being exercised. The combination is technically straightforward — Glennan (2017) explicitly bridges mechanism and powers in 'The New Mechanical Philosophy.' Bird (2007) also sees natural compatibility. The pair forms a contemporary metaphysical package: entities have dispositional powers (POW), mechanisms are organized assemblies of such entities (MEC), and explanation works by identifying the mechanism (MEC) and unpacking the powers it manifests (POW)." },

  // CATEGORY THEORY (CT)
  { from: "ct", to: "sr", type: "grounds",
    note: "CT provides the rigorous mathematics for SR's claim that relations are primary — objects defined by morphisms.",
    detail: "SR's central claim — objects are defined by their relational position rather than intrinsic essence — has a precise mathematical realization in category theory. The Yoneda lemma states that an object in a category is fully determined by its morphisms to (or from) every other object: A ≅ Hom(–, A) as a functor. This is SR made formal: 'objects ARE their relational profile.' Category theory thus serves as SR's natural mathematical home — providing not just a metaphor but theorems making SR's commitments concrete. Bain (2013) argues ontic SR is best formulated in categorical terms; Halvorson and others have developed categorical structural realism in philosophy of physics." },

  { from: "ct", to: "it", type: "compatible",
    note: "Categorical IT exists (Cohen, Coecke); Shannon IT expressible categorically.",
    detail: "Categorical formulations of information theory exist and have grown in the 2010s-2020s: Baudot & Bennequin (2015) develop entropy as a functor satisfying axiomatic chain rules; Coecke and collaborators have categorical quantum information theory (CQIT) using monoidal categories for quantum protocols. The categorical formulation: information channels are morphisms in a category of probability spaces; data processing inequality is functoriality of certain entropy functors. The categorical view unifies classical and quantum information theory and exposes their formal commonalities. CT doesn't replace Shannon IT but provides a substrate-free generalization." },

  { from: "ct", to: "cm", type: "compatible",
    note: "ε-machines have categorical structure (process categories, monoidal compositions).",
    detail: "Crutchfield's ε-machines, viewed categorically, are finite-state machines in a category of processes — morphisms are state transitions, composition is sequential processing. The minimal-sufficient property of ε-machines has a categorical reformulation in terms of universal properties (minimality up to isomorphism). Spivak and others have developed compositional process theories that subsume CM as a special case. The compatibility is structural: CM's results survive categorical generalization, and categorical CM may generalize to richer process settings (quantum, partial-observation) more cleanly than the original probabilistic formulation." },

  { from: "ct", to: "ci", type: "compatible",
    note: "String diagrams for SCMs (Jacobs, Kissinger, Zanasi 2019) — categorical causal inference.",
    detail: "Jacobs, Kissinger & Zanasi (2019, 'Causal Inference by String Diagram Surgery') reformulate Pearl's structural causal models in the categorical language of string diagrams (graphical calculi for monoidal categories). Do-interventions become specific diagrammatic surgeries; the do-calculus's rules become diagrammatic rewrites. The categorical formulation makes precise what's structural in causal inference vs what's specific to particular interventional setups, and it generalizes naturally to quantum causal inference. CT doesn't replace Pearl's framework but gives it a more abstract setting where its essential structure is visible." },

  { from: "ct", to: "net", type: "compatible",
    note: "Networks as objects in a category of relational structures; functorial mappings between graph types.",
    detail: "Network science maps onto category theory naturally: graphs are objects, graph homomorphisms are morphisms, and you get a category Grph. Different graph types (directed, weighted, multigraphs, hypergraphs) are different categories, with functors between them. Spivak's work on databases, scientific schemas, and open dynamical systems treats networks categorically. The interface is more than vocabulary: categorical machinery makes compositional questions about networks tractable (composing networks via shared interfaces, identifying functorial invariants across network types). Applied category theory has substantial network-science applications." },

  // CYBERNETICS (CYB)
  { from: "cyb", to: "net", type: "grounds",
    note: "Networks of feedback loops were the original cybernetic subject — predates modern network science.",
    detail: "Cybernetics in the 1940s-1960s was the first systematic study of networks of feedback loops — Wiener's communication-and-control framework was already explicitly network-theoretic. The Macy Conferences (1946-1953) brought together early network thinking with feedback theory. When modern network science emerged in the late 1990s (Watts-Strogatz, Barabási-Albert), much of its conceptual scaffolding had been pre-figured by cybernetics. The grounding is historical-conceptual: network science inherited from cybernetics the basic idea that system behavior arises from the structure of relationships, not just node properties. Modern NET often forgets this lineage but it's there." },

  { from: "cyb", to: "aif", type: "grounds",
    note: "Active inference inherits second-order cybernetic structure: observer-as-part-of-system.",
    detail: "Active inference is, in important respects, formalized second-order cybernetics. Conant & Ashby's (1970) theorem 'every good regulator of a system must be a model of that system' is FEP's direct ancestor: a system that maintains itself against perturbation must internally model the perturbations. Friston has acknowledged this lineage explicitly. AIF adds the variational-inference mathematical machinery (KL divergence, generative models, gradient flow) that cybernetics didn't have, but the conceptual structure — regulator must model the regulated, observer is part of the system, self-maintenance via predictive modeling — is cybernetic in origin." },

  { from: "cyb", to: "mec", type: "compatible",
    note: "Mechanisms with feedback ARE cybernetic systems. CYB predates and partly grounds MEC.",
    detail: "Many of MEC's canonical examples — homeostatic systems, regulatory networks, neural circuits — were originally cybernetic systems. Cybernetics didn't have MEC's developed criteria for componential decomposition, but it had the central idea of organized assemblies producing system-level behavior. Modern MEC implicitly incorporates feedback-structure analysis whenever it deals with regulatory mechanisms (which is most of biology). The compatibility is strong: a mechanism with feedback loops IS a cybernetic system, just described in different vocabulary. Bechtel (2012, 'Discovering Cell Mechanisms') treats cybernetic ideas as part of MEC's intellectual heritage." },

  { from: "cyb", to: "ci", type: "uses",
    note: "Cybernetics uses causal feedback structures; modern CI formalizes the dynamics.",
    detail: "Cybernetic systems are by definition causal — they involve closed loops of cause and effect (control → effect → measurement → control). Cybernetics anticipated many causal-inference ideas: distinguishing correlation from regulation, identifying feedback loops, understanding intervention. Pearl's formal causal-inference machinery (do-calculus, SCMs) provides the rigorous mathematical treatment cybernetics lacked. Modern dynamic causal modeling in neuroscience (Friston et al.) explicitly bridges cybernetics and CI. CYB uses CI tools when it needs to be quantitatively rigorous about causal structure; classical cybernetics was largely informal about exactly how it claimed causation worked." },

  { from: "cyb", to: "e4", type: "grounds",
    note: "Second-order cybernetics (von Foerster, Maturana) directly fathered enactivism (Varela was Maturana's student).",
    detail: "The lineage is direct and historically documented. Heinz von Foerster developed second-order cybernetics in the 1970s — observer-as-part-of-system, self-referential systems. Humberto Maturana, working in second-order cybernetics, developed autopoiesis with Francisco Varela in the early 1970s. Varela then extended autopoiesis into enactivism (with Thompson and Rosch, 'The Embodied Mind' 1991). So 4E cognition is a literal intellectual descendant of cybernetics — the embodied/embedded/enacted framing is what you get when you take second-order cybernetics seriously about biology. Modern enactivists (Di Paolo, Thompson) are aware of and explicit about this lineage." },

  { from: "cyb", to: "pc", type: "uses",
    note: "Cybernetic control draws on dynamical systems theory for stability analysis.",
    detail: "Cybernetic control theory uses dynamical-systems mathematics throughout: stability of feedback loops via Nyquist criteria, pole placement, Lyapunov analysis. Modern control theory (Kalman onwards) is essentially the mathematical successor of cybernetics, built on PC foundations. Without dynamical systems theory, cybernetics couldn't analyze when feedback loops stabilize vs oscillate vs diverge. The dependency is technical: cybernetics provides the conceptual framework (feedback, regulation, control) while PC provides the math (state spaces, eigenvalue analysis, stability theorems). Most working control engineers don't distinguish the two." },

  // PHENOMENOLOGY (PHE)
  { from: "phe", to: "e4", type: "grounds",
    note: "Merleau-Ponty's lived body and Husserl's intentionality directly ground 4E cognition (Thompson, Gallagher are both phenomenologists).",
    detail: "The grounding is direct and historically traceable. Merleau-Ponty's 'Phenomenology of Perception' (1945) — with the lived body as the medium through which a world appears — is foundational for embodied cognition. Husserl's intentionality and analysis of the temporal structure of consciousness ground enactivist accounts of perception. Modern enactivists Thompson ('Mind in Life' 2007), Gallagher ('How the Body Shapes the Mind' 2005), and Zahavi have backgrounds in phenomenology and explicitly draw on Husserl and Merleau-Ponty. 4E without phenomenology would be a thinner, less philosophically grounded program — and most 4E theorists treat phenomenology as essential." },

  { from: "phe", to: "sr", type: "tension",
    note: "SR's third-person structural realism vs. phenomenology's first-person primary data — distinct methodologies.",
    detail: "SR is a third-person, scientific-realist program: reality consists of structural patterns identifiable in observational/experimental data. Phenomenology takes first-person experience as primary data, irreducible to third-person description. The tension is methodological: SR cannot in principle reach the kind of evidence phenomenology takes as primary; phenomenology questions whether SR's third-person methodology can ever capture the structure of mind. The tension is real and unresolved — and is one form of the broader 'two cultures' problem in philosophy of mind. Naturalizing phenomenology (Petitot, Roy, Varela) attempts a reconciliation; most SR theorists and phenomenologists work in separate conversations." },

  { from: "phe", to: "aif", type: "tension",
    note: "Friston's AIF claims to capture cognition mathematically; phenomenology argues first-person experience is irreducible to inference math.",
    detail: "Active inference claims to provide a comprehensive mathematical theory of cognition: perception is inference, action is inference-guided sampling, learning is parameter inference. Phenomenologists (Gallagher, Zahavi, Thompson) argue this third-person mathematical description leaves out the first-person structure of experience — the lived character of perception, action, attention, mood. Friston has tried to absorb phenomenological insights (recent papers on selfhood, affect), but phenomenologists argue this remains formal description of inference structures, not genuine phenomenological insight. The tension is whether mathematical inference is sufficient OR necessary OR neither for cognition — a deep, active dispute." },

  { from: "phe", to: "sub", type: "opposes",
    note: "Phenomenology rejects the subject/object split that substance metaphysics presupposes.",
    detail: "Substance metaphysics presupposes a clean subject/object distinction: there are substantial entities (objects, including persons-as-substances) with intrinsic natures, and we (subjects) come to know them. Phenomenology rejects this as Cartesian: subject and object co-arise in the structure of experience (intentionality). There's no 'object in itself' separable from how it presents to consciousness, and no 'pure subject' separable from its world. The opposition is foundational, not detail-level: it changes what counts as a basic ontological category. Husserl's phenomenology was developed precisely as an alternative to substance-realism in epistemology." },

  { from: "phe", to: "pcm", type: "opposes",
    note: "Phenomenology: experience is prior to any informational framing. Pancomputationalism is the most extreme third-person reduction.",
    detail: "Pancomputationalism / Information Realism (Wheeler, Wolfram, Tegmark) treats information processing as ontologically fundamental — the universe IS computation, mind included. Phenomenology treats lived experience as primary and irreducible. The opposition is direct: PCM is the most third-person, structurally-reductive ontology available, while PHE is the most first-person, experience-primary ontology available. Each takes the other to miss the central fact about reality (PCM: structure is what's real, experience is derivative; PHE: experience is what's real, structural descriptions are abstractions from it). Few philosophers attempt reconciliation; most pick a side." },

  // 4E COGNITION (E4)
  { from: "e4", to: "aif", type: "tension",
    note: "Both claim to capture cognition. AIF reads cognition as inference; enactivism rejects the inference framing. Active debate (Bruineberg, Kiverstein 2016).",
    detail: "Both frameworks claim to be theories of cognition, but they disagree on the basics. AIF (Friston): cognition IS variational inference under a generative model — fundamentally representational, internalist. Enactivism (Varela-Thompson, Hutto-Myin): cognition is sensorimotor coupling with environment, not internal model-building; basic cognition has no representations. Bruineberg, Kiverstein & Rietveld (2018, 'The Anticipating Brain Is Not a Scientist') argue FEP CAN be read enactively — as gradient flow on free energy without internal model representation — making the two compatible. Standard readings of FEP are internalist; the enactive reading is a minority but growing position. The debate is one of the most lively in current cognitive science." },

  { from: "e4", to: "phe", type: "compatible",
    note: "4E inherits phenomenological insights — embodied, embedded, extended, enacted.",
    detail: "4E and phenomenology are closely allied: 4E inherits the embodied/embedded insights from Merleau-Ponty and Husserl, and uses phenomenological methods to access first-person data about cognition. Many 4E theorists are also phenomenologists (Thompson, Gallagher). The compatibility is robust — 4E provides empirical/biological grounding for phenomenological insights, while phenomenology provides first-person methodology and conceptual framework for 4E. There's no significant disagreement between mainstream 4E and mainstream phenomenology; they're parts of an integrated research tradition. Differences are more about emphasis (4E more empirical, PHE more methodological) than about substance." },

  { from: "e4", to: "pro", type: "compatible",
    note: "Cognition as ongoing process; enactivism naturally process-ontological.",
    detail: "Enactivism's central commitments map onto process metaphysics: cognition is ongoing sensorimotor coupling (process, not state); the organism is autopoietic (a self-producing process); the cognitive system continuously enacts a world rather than passively perceiving fixed objects. Thompson's 'Mind in Life' (2007) explicitly integrates enactivism with process metaphysics via biology. The compatibility is so strong that some readers treat 4E as 'process metaphysics applied to mind.' The combination of process biology (Dupré, Nicholson) with enactive cognition (Varela, Thompson) forms a coherent process-based naturalism about life and mind." },

  { from: "e4", to: "cyb", type: "extends",
    note: "4E extends second-order cybernetics: autopoietic systems engaging environments through sensorimotor loops.",
    detail: "4E doesn't just connect to cybernetics — it directly extends second-order cybernetics. Maturana (a cybernetician) developed autopoiesis; Varela (his student) extended autopoiesis to cognition (enactivism); modern 4E builds on this. The extension adds: (i) phenomenological grounding (Husserl, Merleau-Ponty), (ii) more developed empirical work in cognitive neuroscience, (iii) the extended-mind thesis (Clark & Chalmers 1998). The cybernetic core — closed-loop systems engaging environments through internal-external feedback — is preserved and amplified. 4E IS what second-order cybernetics looks like when applied seriously to biology and cognition." },

  // PANCOMPUTATIONALISM (PCM)
  { from: "pcm", to: "it", type: "grounds",
    note: "Information realism: information is the ontological substrate, and IT is the formal tool to describe it.",
    detail: "Wheeler's 'it from bit' (1990) and information realism (Lloyd, Vedral) take information as ontologically primary: physical reality derives from information processing, not the other way around. This grounds IT as having ontological significance, not just descriptive utility. On this view, Shannon entropy isn't just a measure OF reality, it's a measure of reality itself — the physical universe's basic stuff is bits being processed. IT becomes the natural mathematical framework for fundamental physics on this interpretation. Note this is contested: most physicists and philosophers don't accept information realism, but those who do treat IT as the mathematics of being." },

  { from: "pcm", to: "ait", type: "grounds",
    note: "If reality is computational, AIT's K(x) is the natural measure of structural complexity.",
    detail: "If reality is fundamentally computational (Wolfram, Lloyd, Fredkin), then the Kolmogorov complexity K(x) of a state x is its inherent structural complexity — the length of the minimal program generating it from the universal computation that the universe IS. This grounds AIT ontologically: K isn't just a useful mathematical tool but a measure of how much computation reality 'does' to produce a state. The view runs into the trivialization worry (Putnam, Searle): if every physical system implements every computation, then 'computational complexity of reality' is empty. PCM defenders need non-trivial implementation criteria — work in progress." },

  { from: "pcm", to: "sub", type: "opposes",
    note: "Direct rival: information vs. substance as the ontological base.",
    detail: "The cleanest direct rivalry to substance metaphysics. SUB: there must be substantial entities (with intrinsic natures) bearing properties; information without bearers is incoherent. PCM: information processing is fundamental; 'bearers' are derivative patterns in computational substrate. Each accuses the other of either positing redundant ontology (PCM: 'substance is unnecessary, just patterns of information') or eliminating something obviously real (SUB: 'there must be SOMETHING doing the computing'). The opposition tracks deep choices in metaphysics of physics: substance-friendly interpretations (Bohmian mechanics) vs information-friendly interpretations (QBism, relational QM)." },

  { from: "pcm", to: "pro", type: "tension",
    note: "Both anti-substance, but process metaphysics treats becoming as primary; PCM treats information processing as primary. Compatible at the surface, divergent in detail.",
    detail: "PCM and PRO are both anti-substance ontologies and natural allies against substance metaphysics. But they disagree on what's primary: PRO says becoming (events, occasions of experience) is primary; PCM says information processing is primary. The tension shows up over phenomenal experience: PRO can accommodate experience via Whiteheadian subjective form at every level (panexperientialism); PCM struggles to derive experience from pure computation (the hard problem in PCM-friendly framing). Some thinkers (Tegmark, Chalmers in flirtation) try to combine them: 'every computation has a phenomenal aspect' = computational panpsychism. The combination is uncommon and contested." },

  { from: "pcm", to: "ct", type: "compatible",
    note: "Categorical foundations of computation provide formal language for information ontology.",
    detail: "If reality is computational, what's the rigorous mathematics of that claim? Category theory provides one answer: cartesian closed categories model computation (functional programming), monoidal categories model concurrent/quantum processes, topos theory provides logical foundations for computational reality. Coecke's categorical quantum mechanics is naturally PCM-compatible. Voevodsky's homotopy type theory provides categorical computational foundations for mathematics itself. PCM doesn't require CT, but CT provides the mathematical sophistication PCM needs to be more than a slogan. The combination — categorical foundations + information realism — is one of the more rigorous versions of PCM." },

  // CONSTRUCTOR THEORY (CON)
  { from: "con", to: "at", type: "compatible",
    note: "Walker has bridged AT and CON; Assembly Theory tracks construction histories while Constructor Theory tracks task possibility — related but distinct.",
    detail: "Constructor Theory (Deutsch & Marletto) and Assembly Theory (Walker & Cronin) both make construction primary, but with different primitives. AT: track the assembly index A(x) — the minimum number of joining steps to construct x from primitives. CON: track which tasks (transformations) are physically possible or impossible. Walker has published bridge papers showing AT can be reformulated in constructor-theoretic terms and vice versa. Some see them as the same insight in different vocabulary; others see them as competing programs. The compatibility is real, the boundary is unsettled — both are active research programs whose relationship is currently being worked out." },

  { from: "con", to: "it", type: "tension",
    note: "Marletto's 'constructor theory of information' reformulates IT in task-possibility terms — contested whether it adds content or merely re-expresses.",
    detail: "Marletto (2017, 'Constructor theory of information') reformulates Shannon information theory in constructor-theoretic terms: information is what can be copied (the copy-task is possible), distinguishability is captured by counterfactual task-possibilities. Proponents argue this gives IT new content by basing it on physical possibility rather than abstract distributions. Critics argue it's a notational rephrasing without empirical consequences distinct from standard IT. The tension is unresolved — whether constructor IT IS Shannon IT in different vocabulary, or genuinely captures different facts about information's physical nature. Empirical predictions from constructor IT that distinguish it from standard IT are still scarce." },

  { from: "con", to: "pcm", type: "tension",
    note: "Both anti-substance ontologies but with different primitives: PCM says reality IS computation; CON says reality is task-possibility. Closely allied but not identical.",
    detail: "PCM and CON are both anti-substance: neither requires substantial bearers as fundamental. But their primitives differ: PCM takes computation as fundamental (reality runs programs); CON takes counterfactual task-possibility as fundamental (reality is structured by what tasks are possible vs impossible). PCM is naturally actualist (what exists is the running computation); CON is naturally counterfactualist (what's real includes facts about un-actualized possibilities). The tension matters for: foundations of physics (is the world a computation, or is the world structured by possibility-modalities?), and for what kind of mathematics is foundational (computation theory vs modal logic). Allies against substance, rivals on primitives." },

  { from: "con", to: "th", type: "extends",
    note: "Constructor theory reformulates the second law as facts about impossible heat-transfer tasks — a counterfactual rebuilding of thermodynamics.",
    detail: "Standard thermodynamics: the second law says entropy of an isolated system non-decreases. Constructor theory recasts this as a counterfactual claim: certain heat-transfer tasks (extracting work from a single heat reservoir at uniform temperature) are physically impossible. The extension makes thermodynamics about WHAT'S POSSIBLE rather than about averages over micro-states. Marletto has worked out the constructor-theoretic version of thermodynamic results. The extension hasn't displaced standard thermodynamics but offers a foundational reformulation. Whether the reformulation makes new predictions or just reorganizes the existing theory remains debated." },

  { from: "con", to: "pro", type: "compatible",
    note: "Both treat becoming as primary. Constructor theory is process-friendly mathematical metaphysics for physics.",
    detail: "Constructor theory and process philosophy share an anti-state-substance commitment: what's fundamental is what can be DONE (constructed, transformed, brought about), not what statically IS. Tasks and constructors are inherently process-like — a constructor performs a transformation (a process) while remaining unchanged. Process philosophy provides the qualitative metaphysics; CON provides the mathematical formalization for physics-level applications. They've developed largely independently, but a process-friendly reading of CON is natural. Marletto sometimes describes constructor theory as a way to make process metaphysics mathematically rigorous for physics, though the formal connection isn't fully worked out." },
];

const EDGE_TYPES = {
  opposes:    { color: "#ef4444", label: "opposes",    desc: "Direct rival; contradicting positions",
                dasharray: "7 4",       width: 2.2, terminator: "none",   arrow: false, opacity: 0.9 },
  tension:    { color: "#f59e0b", label: "tension",    desc: "Friction; disagreement on key points",
                dasharray: "2 3",       width: 1.8, terminator: "none",   arrow: false, opacity: 0.8 },
  uses:       { color: "#94a3b8", label: "uses",       desc: "Uses the other's machinery as tool",
                dasharray: undefined,   width: 1.2, terminator: "arrow",  arrow: true,  opacity: 0.55 },
  extends:    { color: "#3b82f6", label: "extends",    desc: "Generalization or special case",
                dasharray: undefined,   width: 1.6, terminator: "double", arrow: true,  opacity: 0.75 },
  grounds:    { color: "#10b981", label: "grounds",    desc: "Provides metaphysical foundation",
                dasharray: undefined,   width: 1.6, terminator: "circle", arrow: true,  opacity: 0.75 },
  compatible: { color: "#14b8a6", label: "compatible", desc: "Coexists; aligns without strict dependence",
                dasharray: "1 4",       width: 1.0, terminator: "none",   arrow: false, opacity: 0.4 },
};

// Two analytical axes, both meaningful:
//   X = mathematical maturity        (qualitative → fully formalized)
//   Y = substrate independence       (substrate-committed ↓ ↑ substrate-free)
// Category (anchor/productive/metaphysical) is shown via color and shape, NOT position.
//
// SUBSTRATE INDEPENDENCE — operational definition:
//   "How much of the framework's machinery works without commitments to
//   *what kind of stuff* the system is made of?"
//
//   High Y  (substrate-free)     : machinery operates on abstract structure
//                                  (bits, graphs, processes) indifferent to
//                                  physical realization. Apply equally to
//                                  neurons, markets, ecosystems, computations.
//
//   Low Y   (substrate-committed): machinery requires specific kinds of stuff
//                                  (physical fields, energy, substances with
//                                  intrinsic natures). Cannot be lifted to
//                                  another substrate without losing content.
//
// NOTE: substrate independence ≠ scope of application. Substance metaphysics
// has wide scope (you can apply substance-talk to anything) but is deeply
// substrate-committed (its machinery REQUIRES substantial bearers with essences).
// Process philosophy explicitly REJECTS substrate priority — so it scores high.
const FW_AXIS = {
  xMin: 130, xMax: 1080,
  yMin: 90, yMax: 720,
};

const FW_LAYOUT = {
  // {maturity 0-100, substrate 0-100}
  // SUBSTRATE INDEPENDENCE notes:
  //   - This measures whether the framework's MACHINERY is portable across substrates,
  //     not whether the framework is typically applied across substrates.
  //     A common confusion: "PC is mostly used in physics, therefore low substrate independence."
  //     But the machinery (state spaces, flows, attractors, bifurcations) is substrate-free —
  //     replicator dynamics, ML training, social dynamics all use PC fluently.
  //   - Where PRO grounds PC/TH, those frameworks should inherit substrate-freedom
  //     for the parts of the machinery that PRO is substrate-free about.
  // ANCHORS
  it:  { maturity: 95, substrate: 95 },   // Operates on any distribution over any alphabet
  sr:  { maturity: 25, substrate: 80 },   // Relations primary; explicitly anti-substance
  // PRODUCTIVE — formal end (substrate-free or near-free)
  ait: { maturity: 92, substrate: 90 },   // K(x) relative to universal Turing machine
  ct:  { maturity: 96, substrate: 92 },   // Pure structural math — most rigorous substrate-free framework
  net: { maturity: 48, substrate: 85 },   // Graphs work on anything relational
  cyb: { maturity: 55, substrate: 75 },   // Feedback/control — substrate-free machinery
  cm:  { maturity: 82, substrate: 70 },   // Stationary processes; abstract but process-bound
  // PRODUCTIVE — middle (substrate-portable machinery, conventional physics framing in practice)
  pc:  { maturity: 88, substrate: 65 },   // State-space + flow machinery is fully portable (replicator dynamics, ML training, ecology, social systems all use PC). PRO grounds PC, so should inherit substrate-freedom.
  ci:  { maturity: 72, substrate: 60 },   // Variables-and-interventions apply broadly; SCMs presuppose discrete causal ontology
  evo: { maturity: 62, substrate: 60 },   // Lewontin's three conditions are substrate-free by design; replicator dynamics work on anything that varies/replicates/selects
  ce:  { maturity: 58, substrate: 58 },   // Transition matrices apply broadly; intervention prior carries some commitments
  // PRODUCTIVE — biology-adjacent (more substrate-bound in practice)
  aif: { maturity: 55, substrate: 45 },   // Markov blanket framework portable in principle; practice is brains/agents
  th:  { maturity: 82, substrate: 45 },   // Stochastic thermodynamics + Landauer principle are substrate-free generalizations. Classical TH still ties to physical temperature, so not fully free. PRO grounds TH (dissipative structures).
  at:  { maturity: 38, substrate: 42 },   // Aims substrate-free; in practice molecular
  // METAPHYSICAL
  pcm: { maturity: 35, substrate: 88 },   // Info-realism: info is substrate-free by claim
  con: { maturity: 30, substrate: 65 },   // Counterfactual primitive — substrate-free in principle, programmatic
  pro: { maturity: 15, substrate: 75 },   // Explicitly anti-substance: "process not stuff"
  cr:  { maturity: 22, substrate: 52 },   // Stratified ontology across physical/bio/social
  pow: { maturity: 32, substrate: 38 },   // Powers need bearers; less than full substance
  e4:  { maturity: 25, substrate: 28 },   // Embodied cognition — body-substrate is essential
  mec: { maturity: 28, substrate: 32 },   // Entities+activities; entities are substantial
  phe: { maturity: 12, substrate: 20 },   // Lived body, embodied experience — body essential
  sub: { maturity: 8,  substrate: 15 },   // CORE COMMITMENT: substances with intrinsic natures
};

function fwPos(key) {
  const slot = FW_LAYOUT[key];
  if (!slot) return null;
  const x = FW_AXIS.xMin + (slot.maturity / 100) * (FW_AXIS.xMax - FW_AXIS.xMin);
  // Y is INVERTED: high substrate-independence is at the TOP (low Y).
  const y = FW_AXIS.yMax - (slot.substrate / 100) * (FW_AXIS.yMax - FW_AXIS.yMin);
  return { x, y };
}

// Soft cluster regions — convex hulls drawn behind nodes
const FW_CLUSTERS = [
  {
    name: "Information & Formal Methods",
    members: ["it", "ait", "ct", "pc", "cm", "th"],
    color: "#06b6d4",
    note: "Rigorously formalized — decades of mathematical machinery",
  },
  {
    name: "Causal Inference Family",
    members: ["ci", "ce", "cm"],
    color: "#f97316",
    note: "Pearl-tradition; interventional and multi-scale extensions",
  },
  {
    name: "Bio-Adjacent Frameworks",
    members: ["evo", "at", "aif", "net", "cyb"],
    color: "#10b981",
    note: "Substrate: biological systems and their analogues",
  },
  {
    name: "Mind & Cognition",
    members: ["aif", "e4", "phe", "cyb"],
    color: "#ec4899",
    note: "Frameworks of cognition, agency, lived experience",
  },
  {
    name: "Anti-Substance Ontologies",
    members: ["sr", "pro", "pcm", "con", "e4"],
    color: "#a855f7",
    note: "Reject substance-as-primary metaphysics",
  },
  {
    name: "Substance-Heavy Ontologies",
    members: ["sub", "pow", "mec"],
    color: "#b45309",
    note: "Require substantial bearers — properties presuppose what bears them",
  },
];

// ─── CLUSTERS ────────────────────────────────────────────────────────────────
const CLUSTERS = {
  "Foundations":              { color: "#a78bfa", short: "FND", desc: "Ontological primitives — what things ARE" },
  "Systems & Structure":      { color: "#60a5fa", short: "SYS", desc: "How parts compose into wholes; what individuates a system" },
  "Dynamics & Time":          { color: "#f472b6", short: "DYN", desc: "Change, flow, history, rates" },
  "Stability & Transition":   { color: "#fbbf24", short: "STA", desc: "Equilibrium, basins, edges between regimes" },
  "Inter-level Structure":    { color: "#22d3ee", short: "ILS", desc: "Mappings, partitions, realization between levels" },
  "Emergence":                { color: "#34d399", short: "EMR", desc: "Novelty from interaction; types and degrees" },
  "Information & Constraint": { color: "#fb923c", short: "INF", desc: "Quantitative measures; what is possible, what carries signal" },
  "Causation":                { color: "#f43f5e", short: "CAU", desc: "Accounts of what causal relations are" },
  "Meta & Agency":            { color: "#84cc16", short: "MTA", desc: "Self-reference, observation, agency" },
};

// ─── CONCEPTS ────────────────────────────────────────────────────────────────
const CONCEPTS = [
  // ═══ FOUNDATIONS ═══
  {
    id: "distinction", name: "Distinction", cluster: "Foundations",
    plain: "The irreducible act of telling two things apart. The minimal unit of structure — requires two relata; one cannot exist without another term to differ from.",
    sr: "Most primitive operation in SR: two nodes are distinguishable iff they differ in at least one relational property. Identity (A=A) is derived — zero-distinction, not a primitive. A thing's identity IS its unique pattern of differences from everything else. A single undifferentiated entity is structurally identical to nothing.",
    it: "Shannon entropy H(X) quantifies average distinguishability — expected bits to specify one draw from X. A system with one state has H=0: zero information, zero structure. The bit is a minimal binary distinction {0,1}. Information theory is the formal science of counting and weighting distinctions.",
    itSym: "𝟙[x≠y] = 1 iff x ≠ y\nH(X) = -Σ p(x) log₂ p(x)  [count of distinctions]\nBit ≡ {0,1}  [minimal binary distinction]\nD_KL(P‖Q) = 0 ⟺ P=Q  [identity = zero-distinction]",
    views: {
      pc: "Phase space X is a set of distinguishable states. Without distinction there is no state space and no dynamics. The metric d(x,y) formalizes degree of distinction — attractors are regions where distinctions collapse.",
      ait: "K(x) defined only for distinguishable strings. K(x|y)=0 iff x and y are the same distinction-node. AIT formalizes the bit-cost of specifying a distinction.",
      cm: "ε-machine first decides which distinctions between histories are causally relevant (histories with identical conditional futures → same causal state). Distinction is the raw material; ε-machine is the relevance filter.",
      pro: "Whitehead: contrast is constitutive of experience. Without distinction between occasions, no process is possible — distinction and becoming co-arise.",
      sub: "Substance ontology: things differ because they have different intrinsic natures (essences). Distinction follows from essence, not the other way around. SR reverses this order.",
      cr: "Bhaskar: distinctions between strata (empirical/actual/real) are ontological, not epistemic. The distinction between a power and its manifestation is one of the most fundamental.",
    },
    related: ["asymmetry-direction", "basic-unit", "relation", "information-entropy", "mutual-information"],
    decisions: [
      "Is distinction observer-independent or observer-constituted? The thermodynamic argument is decisive: entropy increases without witnesses. Physical states are distinct before any observer labels them.",
    ],
    open: "Whether distinction is purely symmetric (A≠B ⟺ B≠A always) or whether asymmetric distinctions are coherent. The answer determines whether Asymmetry is a genuinely independent primitive or derivable.",
  },
  {
    id: "asymmetry-direction", name: "Asymmetry / Direction", cluster: "Foundations",
    plain: "Directed difference — A→B is not the same as B→A. Irreducible to symmetric distinction: every derivation of direction from purely symmetric relations is circular.",
    sr: "The second irreducible structural primitive. Symmetric distinction generates undirected relational networks — topology without causation. Asymmetry generates directed networks: causal graphs, temporal orderings, logical implication. Ontic SR requires directed structure to account for causation and time; symmetric structure alone cannot deliver it.",
    it: "Transfer entropy TE(X→Y) = I(X_past; Y_future | Y_past) is the directed analogue of MI. While I(X;Y)=I(Y;X) is symmetric, TE(X→Y)≠TE(Y→X) in general — the gap is causal direction. KL divergence D_KL(P‖Q)≠D_KL(Q‖P) also encodes asymmetry: the directed cost of using Q when P is true.",
    itSym: "I(X;Y) = I(Y;X)  [symmetric — not causal]\nTE(X→Y) = I(X_{<t}; Y_t | Y_{<t})\nTE(X→Y) ≠ TE(Y→X)  [asymmetric — causal direction]\nD_KL(P‖Q) ≠ D_KL(Q‖P)  [directed divergence]",
    views: {
      pc: "Flow fields ẋ=f(x) are directed. Dissipative systems break time-reversal symmetry — forward trajectory ≠ reverse. Irreversibility is asymmetry made physical. The semigroup structure (not group) of dissipative dynamics formally encodes one-way direction.",
      ci: "Pearl's causal graphs are directed by construction. The direction A→B encodes do-calculus asymmetry: P(B|do(A)) ≠ P(A|do(B)). Undirected graphs cannot represent interventions. Direction is the minimum additional structure required for causation.",
      ce: "Hoel's causal emergence operates on directed causal graphs. EI(macro)>EI(micro) is a claim about asymmetric causal efficacy — macro interventions produce less uncertain effects. Asymmetric causal structure is what makes emergence measurable.",
      pro: "Process ontology: becoming is intrinsically directed. Time's arrow is not added to process — it IS the direction of process. Causation = the past constitutively shaping the present via prehension.",
      th: "Thermodynamic irreversibility is asymmetry made physically concrete and observer-independent. dS/dt ≥ 0 holds regardless of any observer. This is the strongest evidence that asymmetry is an ontological primitive, not a cognitive imposition.",
      cyb: "Feedback loops are directed circuits. Negative feedback: output opposes input (stabilizes). Positive: output amplifies input (runaway). Loop directionality determines system behavior — no direction, no control.",
    },
    related: ["distinction", "causation", "transfer-entropy", "causal-emergence", "transformation", "dissipative-structure"],
    decisions: [
      "Is asymmetry derivable from symmetric distinction? No — every derivation is circular (Kuratowski's ordered pair definition uses asymmetric set membership ∈; temporal succession already presupposes direction). Asymmetry requires an independent axiom.",
      "Is physical time asymmetry fundamental or a consequence of initial conditions on symmetric laws? Answer determines whether asymmetry is primitive at the physical level or emergent from boundary conditions.",
    ],
    open: "Whether the two primitives (Distinction + Asymmetry) are the minimal complete basis, or whether a single more primitive structure generates both. Currently no candidate for such a structure exists.",
  },
  {
    id: "basic-unit", name: "Basic Unit", cluster: "Foundations",
    plain: "The smallest meaningful element — a state, event, or transition carrying semantic weight.",
    sr: "A node in a relational web; identity is entirely its morphisms. No intrinsic content — the unit IS its relational embedding.",
    it: "Elementary event x ∈ X with surprisal -log p(x). H(X) is expected surprisal — average bits to specify a state. Rare events carry more information per occurrence.",
    itSym: "i(x) = -log₂ p(x)\nH(X) = E[i(x)] = -Σ p(x) log p(x)",
    views: {
      pc: "Discrete state in phase space, or infinitesimal increment in continuous dynamics. The elementary state transition Δx.",
      ait: "An individual string or object with Kolmogorov complexity K(x) — length of shortest program producing it. Not averaged over an ensemble; intrinsic to the instance.",
      cm: "Element of observation alphabet; gets grouped into causal states by the equivalence relation P(future | past = x).",
      pro: "Whitehead's actual occasion: a momentary pulse of becoming. Events / occasions are the basic ontological units, not things. A 'thing' is a longitudinal pattern of occasions.",
      sub: "Aristotelian substance: a discrete, independently-existing entity with an intrinsic nature. The 'unit' presupposes that nature individuates the entity from its surroundings — not the case in pure relational accounts.",
      mec: "An entity (or activity) at the lowest decomposition level relevant to the explanandum. The 'unit' is task-relative: what's a unit at one mechanistic level is a complex mechanism at the next level down.",
    },
    related: ["transformation", "relation", "information-entropy"],
    aiEx: "Single inference call — input context in, output out, becomes fixed history.",
    domEx: "A vote, a heartbeat, a Supreme Court ruling fixing precedent for generations.",
  },
  {
    id: "transformation", name: "Transformation", cluster: "Foundations",
    plain: "A state-to-state mapping. Primary primitive — more fundamental than objects in SR.",
    sr: "The morphism IS the structural element. Objects are just endpoints; the transformation carries the relational content. Composition must be associative.",
    it: "Information channel p(y|x) with capacity C = max I(X;Y). Reversible: C = H(X). Lossy: C < H(X).",
    itSym: "Channel: p(y|x)\nC = max_{p(x)} I(X;Y)\nReversible ⇔ I(X;Y) = H(X)",
    views: {
      pc: "State flow ẋ = f(x) or φᵗ: X → X. Semigroup property φˢ⁺ᵗ = φˢ ∘ φᵗ. Reversibility = symplectic; irreversibility = dissipative.",
      ait: "Computation U(p, x) = y on universal machine U. Transformations themselves have program length; reversible computation has zero algorithmic information cost (Landauer).",
      ci: "Structural equation X = f(parents, noise) in an SCM. Interventions sever the edge from parents.",
      th: "Landauer bound: any logically irreversible transformation dissipates ≥ kT ln 2 per bit erased. Sets the thermodynamic floor on all computation, including biological information-processing.",
      evo: "Transformations between generations: variation, inheritance, selection. The replicator equation ẋ_i = x_i (f_i − ⟨f⟩) is the canonical evolutionary transformation.",
      pro: "Becoming IS the primary category. Transformations are not movements between fixed states but the structure of process itself. There are no 'states to move between' — only the continuous becoming.",
      pow: "A transformation occurs when a power manifests under triggering conditions. The state change isn't fundamental — the underlying disposition meeting its stimulus is.",
      mec: "An activity in the MEC sense: an entity-doing-something-to-produce-an-effect. Transformations are decomposed into the entities involved and the activities they perform.",
    },
    related: ["basic-unit", "composition", "flow"],
    aiEx: "Forward pass — context → attention → MLP → logits.",
  },
  {
    id: "relation", name: "Relation", cluster: "Foundations",
    plain: "Mutual influence between two elements. The foundational ontological category in SR.",
    sr: "Primary. Objects don't pre-exist their relations; the relation constitutes both relata. Strong coupling can dissolve individual identity entirely.",
    it: "Mutual information I(X;Y) — bits by which knowing one variable reduces uncertainty about the other. Symmetric, non-negative; zero iff independent.",
    itSym: "I(X;Y) = H(X) − H(X|Y)\n     = Σ p(x,y) log[p(x,y)/p(x)p(y)]\nI ≥ 0; symmetric",
    views: {
      pc: "Coupling: ẋ = f(x,y), ẏ = g(x,y). Coupling strength ∂f/∂y measures how strongly y influences x's evolution.",
      ait: "Algorithmic mutual information: I(x:y) = K(x) + K(y) − K(x,y). Bits two objects share without ensemble assumptions.",
      ci: "Edge in causal DAG. Direction matters: X→Y ≠ Y→X. MI cannot distinguish; intervention can.",
      aif: "Coupling across Markov blanket. Internal and external states relate only through sensory and active states.",
      net: "Edges are the primary objects in network science. Edge weights encode coupling strength; multiplex networks encode multiple kinds of relation between the same pair of nodes.",
      evo: "Coevolution: when two lineages reciprocally select on each other (predator-prey, host-parasite, symbionts). The coupling itself becomes the unit of evolutionary dynamics — neither evolves independently.",
      ct: "Morphisms ARE relations, formalized at full generality. Hom(A, B) is the set of relations between objects A and B. Composition of morphisms is composition of relations. Category theory IS the mathematics of relation — substrate-free, structure-preserving, compositional.",
      cyb: "Cybernetic relations are control/communication channels. The information content of a relation = channel capacity. Bateson's 'difference that makes a difference' = whether the relation has signal value.",
    },
    related: ["mutual-information", "transformation", "markov-blanket"],
    domEx: "Patron-client bonds reshape both parties; colonial relations transformed colonizer and colonized.",
  },
  {
    id: "composition", name: "Composition", cluster: "Foundations",
    plain: "Chaining transformations to produce compound transformations. Associativity is non-trivial.",
    sr: "Combinatorial fabric of relations. Without associative composition, structural levels cannot exist — no consistent way to stack relations.",
    it: "Data processing inequality: for any chain X → Y → Z, I(X;Z) ≤ I(X;Y). Composition can lose but never create information. Equality iff Y is sufficient for X about Z.",
    itSym: "X → Y → Z (Markov)\nI(X;Z) ≤ I(X;Y), I(X;Z) ≤ I(Y;Z)\nEquality iff Y sufficient",
    views: {
      pc: "Flow composition φˢ⁺ᵗ = φˢ ∘ φᵗ. Cascades produce attractor structure no component has.",
      ait: "K(x,y) ≤ K(x) + K(y|x) + O(log). Compound objects have bounded algorithmic complexity from components.",
      cm: "ε-machine transitions compose: history × symbol → next causal state. Preserves minimal-sufficient property.",
      net: "Path composition: walks in graphs compose. Network walks generalize trajectories. Adjacency matrix powers (A^n) count length-n walks.",
      at: "Composition IS the central data of assembly theory. Assembly index counts the minimum joining operations to construct the object from primitives, reusing intermediate parts.",
      evo: "Evolution by recombination — sexual reproduction, horizontal gene transfer, hybridization — composes existing genetic material. Modular evolution: components evolved separately get composed into new wholes.",
      th: "Free-energy differences are additive over reversible decompositions. For irreversible processes, dissipation accumulates along the composition path (Jarzynski integral over trajectories).",
      ct: "Composition is the ONE non-trivial axiom in the definition of a category: morphisms compose associatively. The fundamental data of structure itself. Applied CT (string diagrams, operads, props) builds entire theories of compositional systems on this foundation.",
    },
    related: ["transformation", "flow", "feedback-loop"],
  },

  // ═══ SYSTEMS & STRUCTURE ═══
  {
    id: "system", name: "System", cluster: "Systems & Structure",
    plain: "Bounded set of interacting components with collective behavior. The boundary is a modeling choice.",
    sr: "Coherent region of the relational web — but coherence is the question, not the answer. What MAKES something a system is structural-causal closure of internal relations relative to external ones.",
    it: "Joint distribution P(X₁…Xₙ) with total correlation TC(X) = Σ H(Xᵢ) − H(X). TC measures internal coupling; TC = 0 means no system, just a collection.",
    itSym: "TC(X) = Σ H(Xᵢ) − H(X)\nTC ≥ 0; TC = 0 ⇔ independent",
    views: {
      pc: "Dynamical system (X, T, φ): state space, time set, flow. Complex adaptive: rules themselves are state variables.",
      aif: "States partitioned by Markov blanket into internal, external, sensory, active states. The partition IS the system.",
      net: "Many systems literally ARE networks: nodes + edges + (optionally) weights, types, directions. Network topology often determines system behavior more than node-level properties — same nodes, different topology, different system.",
      evo: "An evolving system (Lewontin 1970) requires three things: variation among units, heritability across generations, differential fitness based on traits. Any system with all three will evolve — biological, cultural, technological, immunological.",
      mec: "A system IS a mechanism (in the MEC view): entities + activities organized to produce a phenomenon. Identifying the system means identifying the entities, their activities, and how they're organized — not just drawing a boundary.",
      cr: "Open vs closed systems (Bhaskar). Closed systems = experimental setups where one mechanism is isolated; closed systems produce regular event sequences. Open systems = most real systems, where multiple mechanisms interact, producing tendencies, not regularities.",
      sub: "A system is an ordered collection of substances bearing relations. The substances' essential natures determine which arrangements are stable and what kind of system can form. Some systems (organisms especially) themselves count as substantial unities for neo-Aristotelians.",
      pro: "A system is a stabilized process pattern — a Whiteheadian society. 'The system' is just the longitudinal coherence of process; if process stops, the system stops being a system. Direct application to organisms (Dupré, Nicholson).",
      cyb: "A system is anything with: (i) inputs, (ii) outputs, (iii) internal state, (iv) feedback. The cybernetic definition — the most general and the historical original — covers thermostats, organisms, social institutions, ML loops alike.",
      e4: "A cognitive system is a body-environment coupling; its boundaries are enacted moment-to-moment through sensorimotor engagement. There is no 'system' apart from its ongoing world-involvement.",
      ct: "A system is an object in a category of systems, with morphisms representing structure-preserving transformations between systems. Compositional systems theory (Spivak, Fong) makes this precise.",
    },
    related: ["boundary", "markov-blanket", "part-whole"],
    domEx: "The Westphalian state system; a kinship network; a city-state's economic-political-military integration.",
  },
  {
    id: "boundary", name: "Boundary", cluster: "Systems & Structure",
    plain: "What separates a system from its environment. Always actively maintained, never simply given.",
    sr: "Structural feature — the locus where internal and external relational density diverge. Derived from relational topology, not primitive.",
    it: "Markov blanket: smallest set with I(X_int; X_ext | MB) = 0. Conditional independence makes X informationally isolated given its blanket.",
    itSym: "X_int ⊥⊥ X_ext | MB(X)\nMB = parents ∪ children ∪ co-parents",
    views: {
      pc: "Region in state space where internal dynamics dominate external coupling. Maintained by dissipation, repair, immune-like processes.",
      aif: "Defining structure: a system IS a system because it has a Markov blanket. Without blanket, no individuation.",
      ci: "Screening-off set — interventions outside have no effect on internal states given the boundary.",
      net: "Community detection: find subgroups with internal edge density > external. Modularity Q measures partition quality; Louvain, Leiden algorithms find communities. A 'system' in network terms = a community with high Q.",
      evo: "Units of selection: cell vs. organism vs. group. The boundary of the replicating unit determines what selection operates on. Major evolutionary transitions are boundary expansions: from individual cells to multicellular organisms, from organisms to colonies.",
      cyb: "Cybernetic boundary = the surface across which control signals flow. Defined by feedback loop closure, not by physical proximity. Bateson: 'the difference that makes a difference' defines the boundary.",
      e4: "Boundaries are ENACTED, not given. The 'extended mind' (Clark & Chalmers): when a notebook plays the same functional role as memory, it IS part of the cognitive system. The boundary of mind moves with the coupling.",
      phe: "The lived body (Merleau-Ponty) is the original boundary — not a thing in the world, but the medium through which a world appears. The body-environment boundary is constitutive of experience.",
      ct: "Sub-object classifier in a topos. Boundaries become categorical objects with universal properties (limits of inclusion morphisms). Pullbacks of monomorphisms.",
    },
    decisions: [
      "Whether boundaries are observer-imposed (epistemic) or system-intrinsic (ontic) determines whether agents are real or modeled.",
    ],
    open: "Many candidate blankets often exist in complex systems; dynamics may not privilege one. Friston's uniqueness claim is contested (Aguilera, Millidge et al.).",
    related: ["markov-blanket", "system", "free-energy-principle"],
    domEx: "National borders maintained via walls, law, enforcement; ethnic boundaries actively performed and contested.",
  },
  {
    id: "markov-blanket", name: "Markov Blanket", cluster: "Systems & Structure",
    plain: "Minimal set of variables that makes a system conditionally independent of everything else.",
    sr: "Structural locus of individuation. The blanket is what makes a node count as a node — without it, no separable subsystem to have structure of.",
    it: "MB(X) = pa(X) ∪ ch(X) ∪ pa(ch(X)). p(X | MB(X), Y) = p(X | MB(X)) ∀Y ∉ MB. Blanket carries all relevant mutual information.",
    itSym: "I(X; Y | MB) = 0, ∀Y ∉ MB(X)\nMB = pa(X) ∪ ch(X) ∪ pa(ch(X))",
    views: {
      pc: "Boundary of an attractor's domain of influence. Internal dynamics weakly coupled to external once MB held fixed.",
      ci: "Screening-off set in Pearl's framework. Operationally: smallest set such that do-interventions outside don't affect X.",
      ce: "Macro Markov blankets need not coincide with micro blankets. Agent boundaries don't track molecular boundaries.",
      aif: "Defining structure of agency. FEP: persisting systems MUST have a Markov blanket; agents are blanketed systems minimizing free energy.",
      net: "In a DAG, the Markov blanket of node X is: parents(X) ∪ children(X) ∪ parents(children(X)). A pure graph-theoretic definition. The neighborhood needed to predict X.",
    },
    decisions: [
      "Discovered (objective dynamical feature) or imposed (chosen partition)? Determines whether agents are real or modeled.",
    ],
    open: "Aguilera et al. (2022) show that in stochastic systems, FEP-style blankets may not be unique or exist. Friston's mathematical commitments are restrictive in ways often unacknowledged.",
    opposingView: "Aguilera, Millidge, Tschantz & Buckley (2022): in general stochastic dynamical systems, Markov blankets in Friston's strict sense are typically non-unique and often non-existent. The 'every persisting system has a Markov blanket' claim conflates a special-case mathematical structure with a universal feature of biology. If the blanket is a chosen partition rather than a discovered one, the entire FEP edifice loses its claim to objectivity. Practical implication: be skeptical when MB is invoked as a 'natural' boundary in arbitrary dynamical systems.",
    related: ["boundary", "free-energy-principle", "coarse-graining"],
  },
  {
    id: "part-whole", name: "Part-Whole", cluster: "Systems & Structure",
    plain: "Nested relationship of components composing larger structures.",
    sr: "Mereology in structural terms. The whole has relational properties no part has — but this doesn't make whole more fundamental than parts; both are real patterns.",
    it: "Compression: H(whole) ≤ Σ H(parts), equality iff independent. Whole-minus-sum gap = TC, integration, or Φ depending on measure.",
    itSym: "H(whole) ≤ Σ H(parts)\nGap: TC(X) > 0 ⇔ whole > sum",
    views: {
      pc: "Hierarchical dynamics — slow macro variables enslaving fast micro variables (Haken's slaving principle).",
      ce: "Hoel: 'whole' macro level can have strictly greater EI than sum of parts. Causal emergence formalizes part-whole asymmetry.",
      net: "Modular networks: parts are densely connected internal communities; the whole is the inter-community network. Hierarchical modularity = communities of communities.",
      evo: "Multi-level selection: selection operates simultaneously on genes, individuals, groups. Major evolutionary transitions reorganize the part-whole structure — what was a whole (a free-living cell) becomes a part (an organelle).",
      mec: "Mechanistic explanation IS part-whole explanation. The phenomenon at level n is produced by the organized activities of components at level n-1. Mechanistic decomposition reveals the part-whole structure of the explanation.",
      sub: "Aristotelian hylomorphism: the whole substance has form that organizes its matter (parts). A part-of-a-whole is not a substance in its own right — a detached finger is not a finger but flesh. The whole's form is primary.",
      cr: "Each stratum is a part-whole layer with its own emergent powers irreducible to the constituent parts. The whole has powers the parts lack — and these emergent powers are real, not merely descriptive.",
      pro: "Wholes are stable patterns of events; parts are nested patterns within those events. Whitehead's 'societies' nest at multiple scales — the whole is just a higher-order society of constituent societies.",
    },
    related: ["levels-hierarchy", "supervenience", "integrated-information"],
  },
  {
    id: "levels-hierarchy", name: "Levels / Hierarchy", cluster: "Systems & Structure",
    plain: "Nested scales of organization, each with its own dynamics, vocabulary, effective laws.",
    sr: "Real patterns at multiple scales. Levels are scales at which compressible structure exists — not arbitrary. Ladyman & Ross's central commitment.",
    it: "Hierarchy of partitions X → π₁(X) → π₂(π₁(X)) → … with H decreasing as resolution decreases.",
    itSym: "X ⊇ π₁(X) ⊇ π₂(X) ⊇ …\nH(X) ≥ H(π₁) ≥ H(π₂)…",
    views: {
      pc: "Separation of timescales — fast/slow dynamics. Fast variables slaved; slow variables are macro state.",
      cm: "Hierarchical ε-machines: macro causal states at one scale become symbols at the next.",
      ce: "Each level has its own EI. Causal emergence is empirical question of which level maximizes it.",
      net: "Hierarchical networks: nodes at one scale become modules at the next. Networks of networks (multilayer / multiplex networks) explicitly model multi-scale connectivity.",
      evo: "Hierarchy of evolutionary levels: gene, individual, group, species, clade. Different selective pressures operate at each level. The 'levels of selection' debate is exactly about which hierarchy levels are real units of natural selection.",
      cr: "Bhaskar's stratified ontology IS the levels-hierarchy view, in its strongest form. Each stratum has its own emergent powers irreducible to lower strata. Physics → chemistry → biology → psychology → social. Not just descriptive convenience — ontologically real layered structure.",
      mec: "Mechanisms span levels: each component-mechanism at level n is itself a multi-level mechanism. Mechanistic explanation is inherently interlevel. Craver's 'mosaic of mechanisms' across levels.",
      pow: "Higher-level powers emerge from organized lower-level powers, but the higher-level powers are themselves real dispositional features. Emergent powers at the social level (group decision capacities) are not just shorthand for individual powers.",
      sub: "Higher-level substances (organisms, societies) supervene on but are not reducible to lower-level substances. The classical Aristotelian hierarchy: matter → element → mixt → organism — each level has its own substantial form.",
    },
    decisions: [
      "Are levels objective (dynamics-selected) or epistemic (convenience-chosen)? Same question as for Markov blankets.",
    ],
    related: ["coarse-graining", "renormalization", "causal-emergence"],
  },
  {
    id: "mapping-between-systems", name: "Mapping Between Systems", cluster: "Systems & Structure",
    plain: "Structure-preserving translation between domains. Basis of analogy, modeling, abstraction.",
    sr: "Inter-system structural correspondence. Modeling is the claim that such a mapping exists; the relations that survive translation are structural invariants.",
    it: "Sufficient statistic T: X → S with I(X;Y | T(X)) = 0. Information bottleneck: max I(T;Y) − β·I(X;T).",
    itSym: "T sufficient: I(X;Y|T) = 0\nIB: max I(T;Y) − β I(X;T)",
    views: {
      pc: "Topological conjugacy: h ∘ φᵗ_X = φᵗ_Y ∘ h. Two systems dynamically equivalent under h.",
      ait: "Algorithmic equivalence: K(x|y) ≈ K(y|x) ≈ 0 means systems are mutually computable from each other.",
      net: "Graph isomorphism: bijection on nodes preserving edges. Graph homomorphism: structure-preserving but not necessarily invertible. The relational-structure-preserving maps are graph maps.",
      evo: "Homology vs. analogy: homologous structures share evolutionary origin; analogous structures share function via independent paths (convergent evolution). The distinction is fundamentally about which inter-system mapping respects the phylogenetic graph.",
      ct: "Native framework. Functors F: C → D ARE structure-preserving mappings between systems-as-categories. Natural transformations between functors capture 'the same map applied uniformly.' Category theory IS the mathematics of inter-system mapping at full generality.",
      cyb: "Modeling (in Conant-Ashby sense): the regulator must be a model of the system. Effective control requires that a structural mapping exist from system to controller.",
    },
    related: ["composition", "renormalization", "multiple-realizability"],
    domEx: "Comparative politics as systematic system-mapping; failures of mapping democratic forms onto non-Western contexts.",
  },

  // ═══ DYNAMICS & TIME ═══
  {
    id: "flow", name: "Flow", cluster: "Dynamics & Time",
    plain: "Continuous evolution through state space along a vector field.",
    sr: "Temporal-relational structure. Flow defines trajectories on which relations evolve.",
    it: "Directed information I(X^n → Y^n) — temporally cumulative, respects causal direction. Reduces to MI for feedforward; gap measures feedback.",
    itSym: "I(X^n → Y^n) = Σ I(X^i; Y_i | Y^{i-1})\n≤ I(X^n; Y^n), gap = feedback",
    views: {
      pc: "dx/dt = f(x,t). Divergence ∇·f: positive = expansion, negative = dissipation (volume contraction onto attractor).",
      th: "Entropy flow: dS_env/dt = ⟨Q⟩/T. Heat flow IS entropy flow. Non-equilibrium steady states are flow-maintained — they exist BECAUSE entropy is exported.",
      net: "Flow on networks: from random walks (PageRank) to traffic models to epidemics on graphs. Network topology shapes flow patterns; flow patterns reveal effective network structure.",
      pro: "Bergson's duration (durée) — qualitative continuous flow. The primary metaphysical reality is the becoming, not the states it passes through. State-space framings of flow are useful abstractions but they reify what is fundamentally process. The 'arrow on the vector field' is a snapshot of becoming, not its essence.",
      pow: "A flow is the ongoing manifestation of a system's dispositional structure under its current conditions. Different initial states sit in different basins because the powers manifest differently from different starting points — the flow IS the power expressing itself.",
    },
    related: ["transformation", "feedback-loop", "transfer-entropy"],
    domEx: "Migration flows reshaping electorate composition; remittance flows binding diasporas.",
  },
  {
    id: "feedback-loop", name: "Feedback Loop", cluster: "Dynamics & Time",
    plain: "Output of a process re-entering as input. Reinforcing loops amplify; balancing loops stabilize.",
    sr: "Self-referential structure in the relational web. A closed cycle whose dynamics aren't localized in any single relation.",
    it: "Directed information gap between I(X^n → Y^n) and I(X^n; Y^n). Feedback: T(X→Y) > 0 AND T(Y→X) > 0.",
    itSym: "Feedback: T(X→Y) > 0 ∧ T(Y→X) > 0\nDirected info gap quantifies feedback",
    views: {
      pc: "Closed causal cycle. Loop gain determines stability: |gain| > 1 → unstable; < 1 → stable.",
      ci: "Cyclic causal graph. Pearl's standard framework assumes acyclic (DAGs); cyclic causal models require additional machinery.",
      net: "Cycles in directed networks ARE feedback loops. Spectral analysis: feedback strength corresponds to dominant eigenvalues. Strongly connected components of a digraph identify mutually-reachable feedback structures.",
      evo: "Coevolutionary feedback: prey evolution drives predator evolution drives prey evolution. Niche construction (Odling-Smee): organisms modify their environment, which then selects on them.",
      cyb: "Native concept. Cybernetics IS the theory of feedback. Negative feedback stabilizes (homeostasis); positive feedback amplifies (runaway). Loop polarity = net gain sign. Closed-loop transfer function H(s) = G/(1 + GH) is the master formula.",
    },
    related: ["self-reference-closure", "delay-lag", "transfer-entropy"],
  },
  {
    id: "delay-lag", name: "Delay / Lag", cluster: "Dynamics & Time",
    plain: "Time gap between cause and effect. Delays produce oscillation, overshoot, instability.",
    sr: "Temporal extension of relational structure. Delayed relations are qualitatively distinct from instantaneous coupling.",
    it: "Lagged MI I(X_t; Y_{t+τ}). Peak τ* identifies characteristic coupling timescale.",
    itSym: "I(X_t; Y_{t+τ})\nPeak at τ* = characteristic delay",
    views: {
      pc: "Delay differential equation: ẋ = f(x(t-τ)). Simple loops with delay produce Hopf bifurcations and chaos.",
      ci: "In time-series causal inference, lag selection is critical — Granger causality assumes correct lag structure.",
    },
    related: ["feedback-loop", "path-dependence", "transfer-entropy"],
    domEx: "Marketing today → traffic in weeks; brand investment → trust in years.",
  },
  {
    id: "path-dependence", name: "Path Dependence", cluster: "Dynamics & Time",
    plain: "Current state depends not just on present conditions but on trajectory taken to reach it.",
    sr: "Non-Markovian relational structure — relations encode history. Structure at time t depends on full path, not just x(t).",
    it: "Memory: I(X_t; X_{<t-k}) > 0 even for large k. Excess entropy E = I(past; future) quantifies stored history.",
    itSym: "E = I(past; future)\n  = lim H(X^L) − L·h_μ\nE > 0 ⇔ path-dependent",
    views: {
      pc: "Non-Markovian dynamics. Hysteresis: same parameters yield different states depending on path.",
      ait: "K(x_t | x_0) grows over time as path information accumulates; logical depth (Bennett) measures how much computation history is required.",
      cm: "ε-machine memory states beyond immediate observation — Cμ > 0 means path information required for prediction.",
      evo: "Phylogenetic constraint — current variation is bounded by lineage history. Gould's 'replay the tape' thought experiment: contingency rules out unique trajectories. The frozen accident: present mammalian eye design constrained by what early chordates happened to have.",
      net: "Network growth models with attachment kernels are path-dependent: who arrived early and what they connected to determines final topology. First-mover advantage as graph structure.",
    },
    related: ["delay-lag", "metastability", "epsilon-machine"],
    domEx: "QWERTY keyboard persistence; institutional lock-in; constitutional precedent shaping centuries.",
  },

  // ═══ STABILITY & TRANSITION ═══
  {
    id: "attractor-basin", name: "Attractor / Basin", cluster: "Stability & Transition",
    plain: "Region of state space the system flows toward. Basin = set of initial conditions arriving there.",
    sr: "Real structural feature of the dynamics. Basin partition is dynamics-selected — not arbitrary, not observer-imposed.",
    it: "Information about initial condition decays within basin. Surviving information identifies basin: I(x_0; x_t) → log(#basins) as t → ∞.",
    itSym: "I(x_0; x_t) → log(#basins)\nBasin info = H(basin label)",
    views: {
      pc: "Lyapunov function decreasing toward fixed point, limit cycle, torus, or strange attractor. Stable: small perturbations decay.",
      cm: "Asymptotic causal states correspond to basins — what survives the past is which basin.",
      ce: "Basin partition often coincides with EI-maximizing partition. Natural alignment between dynamics and causal emergence.",
      aif: "Expected states for the system. FEP: agents act to remain in their basin (= minimize surprise).",
      evo: "Fitness landscape: trait space with fitness as height. Adaptive peaks ARE attractor basins; selection drives populations uphill toward local maxima. Wright's shifting balance theory describes basin transitions in evolving populations.",
      th: "Quasi-potential landscape for non-equilibrium systems generalizes equilibrium energy landscapes. Basin depth = NESS escape time.",
      pow: "An attractor basin IS a dispositional structure — the system's disposition to converge to that attractor under perturbation. Different basins = different macro-dispositions of the same underlying system. The geometry of state space encodes powers.",
      pro: "An attractor is a stable process pattern — a way of becoming that the system keeps re-instantiating. The basin is the set of process-paths that converge to that pattern. Process metaphysics naturally accommodates dynamic stability without substance commitment.",
      cr: "Generative mechanisms drive systems toward characteristic outcomes (attractors). In open systems, multiple basins reflect multiple mechanisms competing; in closed systems, one basin dominates. Attractor analysis is mechanism analysis at the dynamical level.",
    },
    decisions: [
      "Attractor basins are the strongest candidate for objective macro-partitioning — dynamics select them.",
      "But systems with many attractors and fractal basin boundaries undermine clean partition claims.",
    ],
    related: ["metastability", "dissipative-structure", "coarse-graining"],
    domEx: "Failed states (Somalia, late-Yugoslavia) pushed past basin boundary into different attractor.",
  },
  {
    id: "metastability", name: "Metastability", cluster: "Stability & Transition",
    plain: "Stable on intermediate timescales, ultimately decaying. Most real macroscopic structure is metastable.",
    sr: "Real structures with finite lifetime. Being temporary doesn't undermine reality at the relevant timescale.",
    it: "Info about which metastable state is occupied decays slowly with τ_meta. For t < τ_meta, state label is informationally meaningful.",
    itSym: "Exit time ~ exp(ΔE/kT)\nI retained for t < τ_meta",
    views: {
      pc: "Local minima with finite barriers. Cells, organisms, ecosystems are all metastable. Timescale separation makes coarse-graining work.",
      ce: "Regime where most emergence-claims live. Information loss into metastable basin generates new macro structure.",
      aif: "Markov-blanketed systems are metastable. Death = exit from blanket-maintaining attractor.",
    },
    related: ["attractor-basin", "dissipative-structure", "renormalization"],
  },
  {
    id: "phase-transition", name: "Phase Transition / Bifurcation", cluster: "Stability & Transition",
    plain: "Qualitative change in system behavior as parameter crosses critical value. Attractor structure itself changes.",
    sr: "Discontinuity in relational structure at criticality. Symmetry breaking: G → H ⊂ G, new order parameter ψ ≠ 0.",
    it: "MI diverges at second-order critical points: I → ∞ as ξ → ∞ (correlation length). Long-range order from short-range interactions.",
    itSym: "At T_c: ξ → ∞, I → ∞\n⟨φ(0)φ(r)⟩ ~ r^{-η}",
    views: {
      pc: "Bifurcation in f(x; μ) at μ_c. Order parameter goes 0 → nonzero. RG universality classes collapse vast micro-families to same critical behavior.",
      ce: "Phase transitions often produce strongly causally emergent regimes. Macro order parameters carry causal information not present below transition.",
      net: "Percolation: as edge density crosses p_c, a giant connected component appears. Classical phase transition on graphs. Scale-free network percolation has p_c → 0, making them robust to random failure but fragile to targeted attack.",
      evo: "Major evolutionary transitions (Maynard Smith & Szathmáry 1995): unicellular → multicellular, solitary → eusocial, signal → language. Each transition is a phase change in WHAT the unit of selection is — irreversible reorganization of the evolutionary hierarchy.",
      th: "First-order transitions involve latent heat — finite entropy jumps. Second-order transitions show diverging fluctuations and correlation length. Stochastic thermodynamics extends both to driven, non-equilibrium settings.",
    },
    open: "Whether biological 'phase transitions' (cell differentiation, ecosystem regime shifts) are formally analogous to physical ones or merely metaphorical remains contested.",
    related: ["renormalization", "criticality-edge-of-chaos", "novelty-creativity"],
    domEx: "Tipping points in revolutions; ecosystem regime shifts; cultural paradigm transitions.",
  },
  {
    id: "criticality-edge-of-chaos", name: "Edge of Chaos / Criticality", cluster: "Stability & Transition",
    plain: "Parameter regions where system is poised between order and chaos. Maximum computational capacity and adaptability.",
    sr: "Structural regime with maximum non-trivial pattern — neither frozen (ordered) nor random (chaotic).",
    it: "Statistical complexity Cμ peaks at edge of chaos. Maximum MI between subsystems. Power-law correlations.",
    itSym: "Cμ peaks near critical point\n⟨...⟩ ~ power laws\nLyapunov λ ≈ 0",
    views: {
      pc: "Lyapunov exponent λ ≈ 0 — neither contracting nor expanding. Self-organized criticality (Bak): systems drive to critical states.",
      ait: "Maximum logical depth at criticality — most computation history required to reach the state from any simple description.",
      cm: "Maximum ε-machine complexity. Critical systems are computationally rich — neither trivial nor random.",
    },
    open: "Criticality hypothesis for brain function — neural dynamics operating near criticality for optimal information processing — has supporting but contested evidence.",
    related: ["phase-transition", "self-organization", "complexity-scale-free"],
  },
  {
    id: "dissipative-structure", name: "Dissipative Structure", cluster: "Stability & Transition",
    plain: "Ordered structure sustained by continuous energy dissipation. Far from equilibrium, dissipation generates order.",
    sr: "Real macro structure with properties no equilibrium analog has. Order parameters at macro scale are new structural elements, not redescriptions.",
    it: "Internal information increase paired with environmental entropy export: dS_sys < 0 only if dS_env > 0, total dS > 0.",
    itSym: "dS_total = dS_sys + dS_env > 0\nWith dS_sys < 0 possible",
    views: {
      pc: "Prigogine. Bénard cells, Belousov-Zhabotinsky, life itself. Stable far-from-equilibrium attractors maintained by energy throughput.",
      ce: "Canonical case for selective information loss generating new structure — the mechanism behind macro causation in living systems.",
      aif: "Living systems ARE dissipative structures with Markov blankets. FEP claims this isn't coincidence but mathematical necessity.",
      th: "Modern formalization: Non-Equilibrium Steady States (NESS) with quantified entropy production σ ≥ 0. Schnakenberg cycle decomposition gives σ from currents on the state-transition graph. Jarzynski/Crooks fluctuation theorems quantify rare reversal probabilities. Prigogine made precise.",
      evo: "Living dissipative structures are also evolutionary structures: they vary, replicate, and undergo selection. England's hypothesis: evolutionary success and thermodynamic dissipation are correlated — surviving lineages are those that better dissipate driving gradients.",
    },
    related: ["metastability", "free-energy-principle", "self-organization"],
    domEx: "Organisms as dissipative structures; cities as energy-throughput-maintained order; civilizations as sustained-by-flow structures.",
  },
  {
    id: "renormalization", name: "Renormalization Group", cluster: "Stability & Transition",
    plain: "Systematic procedure for moving between scales by integrating out high-frequency modes. What survives IS the real macro structure.",
    sr: "Mathematical machinery of structural realism in physics. RG fixed points are scale-invariant — precisely what's real across levels.",
    it: "RG transformations are coarse-grainings. Universality classes: same RG fixed point = same macro structure regardless of micro details. Formalizes multiple realizability rigorously.",
    itSym: "Scale: Λ → bΛ\nFlow: K_{n+1} = R[K_n]\nFixed pt: K* = R[K*]",
    views: {
      pc: "Wilson's framework. Relevant operators scale up; irrelevant operators die. Marginal operators tune behavior.",
      ait: "Coarse-graining as algorithmic compression. The RG-flowed theory has lower K than the original because irrelevant degrees of freedom are dropped.",
      cm: "Hierarchical ε-machines are information-theoretic analog. RG and CM agree on what should survive coarse-graining.",
      ce: "RG universality is most rigorous case of multiple realizability and supports CE: macro behavior independent of (most) micro details.",
    },
    open: "RG works rigorously in physics. Extension to biology, ecology, cognition is suggestive but not yet rigorous despite many attempts (Mora & Bialek, others).",
    related: ["coarse-graining", "multiple-realizability", "phase-transition"],
  },
  {
    id: "resilience", name: "Resilience", cluster: "Stability & Transition",
    plain: "Capacity to absorb perturbation without basin transition. Distinct from robustness (resistance to all change).",
    sr: "Structural property quantifying basin geometry: depth and width of attractor in state space.",
    it: "Information about basin label preserved under perturbation: I(basin_t; basin_0) → high even under noise.",
    itSym: "Mean exit time τ_e from basin\nLogarithmic in basin depth",
    views: {
      pc: "Basin width and depth in state space. Resilience = perturbations system can absorb without exiting basin.",
      aif: "FEP: capacity to return to expected states under perturbation. Minimizing free energy IS resilience.",
    },
    related: ["attractor-basin", "metastability", "feedback-loop"],
  },
  {
    id: "nonlinearity", name: "Nonlinearity", cluster: "Stability & Transition",
    plain: "Output not proportional to input. Source of feedback, multiple equilibria, chaos, and most interesting complexity.",
    sr: "Relations don't compose additively. Whole differs from sum of parts because combination rule is non-additive.",
    it: "Information measures detect nonlinearity that correlation misses: high MI with low Pearson ρ indicates nonlinear coupling.",
    itSym: "ρ(X,Y) ≈ 0 but I(X;Y) > 0\n⇒ nonlinear coupling",
    views: {
      pc: "f(αx + βy) ≠ αf(x) + βf(y). Required for chaos, bifurcation, hysteresis, multistability.",
      ci: "Nonlinear SCMs require functional-form assumptions for identifiability. Linear Gaussian SCMs are convenient but special.",
      pow: "Nonlinearity reflects threshold-triggered powers: a disposition that activates only above some stimulus level produces a non-additive response. Mumford & Anjum: 'powers are inherently non-additive' — their composition is generally not linear superposition but more like vector-sum-with-interference.",
    },
    related: ["phase-transition", "feedback-loop", "criticality-edge-of-chaos"],
  },

  // ═══ INTER-LEVEL STRUCTURE ═══
  {
    id: "coarse-graining", name: "Coarse-Graining (Quotient Map)", cluster: "Inter-level Structure",
    plain: "Mapping that identifies distinct microstates as the same macrostate. A quotient, not a compression — generates new relations.",
    sr: "Structure-TRANSFORMING (not preserving) map between levels. Not a homomorphism but a quotient. New relations on equivalence classes have no analog at micro level. The central mechanism of inter-level structure.",
    it: "Many-to-one π: X → Y with p(y) = Σ p(x), x∈π⁻¹(y). DPI: I(Y;Z) ≤ I(X;Z). Cannot increase info about external Z — but can generate internal structure absent at micro.",
    itSym: "π : X → Y, many-to-one\nDPI: I(Y;Z) ≤ I(X;Z)",
    views: {
      pc: "Macroscopic variables in stat mech. Adiabatic elimination (Haken): integrate out fast variables for effective slow dynamics.",
      ait: "Algorithmic compression: K(π(x)) ≤ K(x) + O(log). Good coarse-grainings yield K(macro) << K(micro).",
      cm: "Canonical partition: x ~ x' iff P(future|x) = P(future|x'). Discovered, not chosen.",
      ce: "Right partition maximizes EI = I(I_D; E_D) at macro scale. Computable from transition matrix.",
      ci: "Partition must be intervention-consistent: do(Y=y) must yield same effect regardless of which microstate realizes y.",
      ct: "Coarse-graining is a functor from a category of detailed dynamical systems to a category of coarser ones, factoring through a quotient. Spivak has formalized open systems and coarse-graining functorially. The conditions for a 'good' coarse-graining become functoriality conditions.",
      cyb: "Cybernetic coarse-graining: keep what's needed for the regulator, discard the rest. Conant-Ashby gives the criterion — the macrostate must preserve enough structure for regulation to remain possible.",
    },
    decisions: [
      "Observer-chosen partition → macro emergence is partly cognitive.",
      "Dynamics-selected partition → macro emergence is objective but requires privileged scale.",
      "Both → need to explain why they align (Hoel and Crutchfield largely show empirically that they do).",
    ],
    open: "Whether dynamics-selected and EI-maximizing partitions always coincide is empirical regularity, not theorem.",
    related: ["microstate-macrostate", "epsilon-machine", "effective-information"],
  },
  {
    id: "microstate-macrostate", name: "Microstate / Macrostate", cluster: "Inter-level Structure",
    plain: "Two descriptions of same system at different resolutions. Macrostate identifies many microstates as equivalent.",
    sr: "Both real structural levels. Macrostate is not redescription — it instantiates distinct relational pattern at its own scale. Ladyman & Ross's rainforest realism.",
    it: "Macro M = π(X), H(M) ≤ H(X). Compression ΔH = H(X) − H(M) ≥ 0 is information sacrificed. H(X|M) > 0 quantifies within-class entropy = multiple realizability.",
    itSym: "M = π(X), H(M) ≤ H(X)\nΔH = H(X) − H(M) ≥ 0",
    views: {
      pc: "Microstate: full molecular configuration. Macrostate: temperature, pressure, density. Stat mech formalizes the link.",
      ait: "K(macro) can be much less than K(micro) if macro captures regularity; or comparable if micro is already compressible.",
      cm: "Macrostate = causal state when chosen properly. Otherwise it's a bad coarse-graining.",
      ce: "Either level can have higher EI depending on partition — empirical question.",
    },
    related: ["coarse-graining", "supervenience", "multiple-realizability"],
  },
  {
    id: "supervenience", name: "Supervenience", cluster: "Inter-level Structure",
    plain: "B-properties supervene on A iff no B-difference without A-difference. Standard inter-level dependence.",
    sr: "Macro structure depends on micro: no macro change without micro change. But supervenience doesn't entail reduction — macro can be multiply realized.",
    it: "If M supervenes on X: H(M|X) = 0. Reverse fails: H(X|M) > 0 generally. Asymmetry of supervenience = asymmetry of conditional entropy.",
    itSym: "M sup X: H(M|X) = 0\nH(X|M) > 0 generally",
    views: {
      pc: "Macro states determined by micro states (ensemble average). Same macro state realized by many micro configurations.",
      ce: "CE is compatible with supervenience — macro causation can be more informative without violating physical closure.",
    },
    decisions: [
      "Strong supervenience + multiple realizability → macro is real and irreducible",
      "Supervenience alone doesn't explain WHICH macro patterns are real (need real-pattern, ε-machine, or EI criterion).",
    ],
    related: ["multiple-realizability", "microstate-macrostate", "strong-emergence"],
  },
  {
    id: "multiple-realizability", name: "Multiple Realizability", cluster: "Inter-level Structure",
    plain: "Same macro pattern instantiated by many distinct micro configurations. Pain by neurons, possibly by silicon.",
    sr: "Central evidence for autonomy of higher levels. If same structure has many realizers, the structure itself is real — realizers are interchangeable.",
    it: "|π⁻¹(y)| > 1 — many microstates map to same macrostate. H(X|Y) > 0 quantifies within-class variability lost in coarse-graining. MR is the conditional-entropy reading of multiple realization.",
    itSym: "MR ⇔ |π⁻¹(y)| > 1 for some y\n⇔ H(X|Y) > 0\nWithin-class entropy = realizer slack",
    views: {
      pc: "RG universality is the rigorous physical form: micro-Hamiltonian details collapse to same macro critical behavior at fixed point.",
      cm: "Different micro mechanisms can produce same ε-machine — the ε-machine is the real causal structure.",
      ce: "MR is necessary for CE but not sufficient. Also need macro EI > micro EI.",
      evo: "Convergent evolution — eyes evolved independently 40+ times, flight 4+ times, eusociality 11+ times. Same adaptive peak reached by distinct phylogenetic paths. The strongest empirical case for multiple realizability outside physics.",
      at: "Same molecular target can be reached by many assembly paths. The minimum assembly index is canonical; alternative paths to the same product are realizers of the same end-state.",
    },
    opposingView: "Type-identity theory (Place 1956; Smart 1959; Lewis 1969): mental/macro types ARE physical types — same kind of mental state IS the same kind of physical state. Bechtel & Mundale (1999) argued classic MR claims overstate cross-species differences; with finer-grained types you get type-identity back. The 'multiple realizability' might be artifact of coarse type-individuation. If true, special-science autonomy is illusory and reduction is in principle possible.",
    related: ["renormalization", "supervenience", "epsilon-machine"],
  },
  {
    id: "real-pattern", name: "Real Pattern", cluster: "Inter-level Structure",
    plain: "Dennett — a pattern is real iff describing it compresses predictive information beyond available alternatives.",
    sr: "Cornerstone of Ladyman & Ross's ontic SR. What exists is real patterns at multiple levels. Physics→Biology→Cognition hierarchy is real to extent each level carries non-redundant pattern.",
    it: "Compressibility criterion. Operationalized via MDL, predictive information, excess entropy.",
    itSym: "Real: K(d) > K(P) + K(d|P)\nMDL: shorter description = more real",
    views: {
      pc: "Macroscopic order parameters in stat mech. Order parameter = real pattern.",
      ait: "Native framework: pattern P is real iff K(data) > K(P) + K(data|P). Kolmogorov-based definition.",
      cm: "Causal states are real patterns par excellence — minimal sufficient statistics.",
      ce: "Real patterns at EI-maximizing scale are 'most real' in the causal sense.",
      ct: "A real pattern is what's preserved by functorial mappings. Categorical: if F: C → D is a structure-preserving functor and π is a 'pattern' in C, then F(π) is the same pattern in D. Real patterns are invariants under structure-preserving translation — exactly the categorical notion.",
      cyb: "Patterns regulators can latch onto. A real pattern, cybernetically: a structure stable enough that a regulator can model and exploit it without continual recalibration.",
    },
    decisions: [
      "Realism = compressibility → potentially many real patterns coexist; partition partly observer-dependent.",
      "Realism requires causal power → MDL alone insufficient; need EI or interventional grounding.",
    ],
    open: "Dennett's criterion is epistemic (about describers). Ladyman & Ross want it ontological. The slide isn't justified by the criterion itself.",
    opposingView: "Eliminativism (and related anti-emergentism): there are no real patterns beyond the most fundamental physical level. What looks like a 'real pattern' at higher scales is just our cognitive convenience — the underlying physics is the only reality. The compressibility criterion measures our descriptive limits, not ontological structure. If pushed hard, this view denies that 'beech-maple forest' or 'GDP' have any reality independent of describers.",
    related: ["coarse-graining", "epsilon-machine", "effective-information"],
  },
  {
    id: "epsilon-machine", name: "ε-machine / Causal States", cluster: "Inter-level Structure",
    plain: "Crutchfield's minimal sufficient predictor. Causal states are equivalence classes of histories with identical conditional futures.",
    sr: "Objectively privileged structural level for prediction. The ε-machine is what the system's structure looks like with all redundancy removed.",
    it: "σ(h) = {h' : P(future|h') = P(future|h)}. Statistical complexity Cμ = H(causal states). Excess entropy E = I(past; future).",
    itSym: "h ~ h' iff P(f|h) = P(f|h')\nCμ = H(S) (minimal)\nE = I(past; future)",
    views: {
      pc: "Computational mechanics framework. ε-machine generates same statistics as original process with minimum internal states.",
      ait: "Closely related: K(generative model) is bounded by Cμ when the process is computable. Both seek minimal description.",
      ce: "Often coincides with EI-maximizing partition but not always. ε-machines optimize prediction; EI optimizes causal power.",
    },
    decisions: [
      "ε-machine is unique up to isomorphism. Unlike EI-maximization (partition search), causal states are DISCOVERED, not chosen.",
    ],
    opposingView: "Hidden Markov Models (and successors): older, more flexible formalism. HMMs don't claim minimality but are easier to estimate from data — practical alternative when objectivity claims are less important than tractability. Reservoir computing / echo state networks: random recurrent dynamics capture temporal structure without principled minimality. Predictive state representations (Littman, Singh): similar idea in RL formalism, often more practical. The uniqueness-up-to-isomorphism claim is also weaker than it sounds — different isomorphic ε-machines can still mean different things scientifically.",
    related: ["coarse-graining", "real-pattern", "causal-emergence"],
  },

  // ═══ EMERGENCE ═══
  {
    id: "emergence-general", name: "Emergence", cluster: "Emergence",
    plain: "Collective behavior or properties arising at a higher level not obvious from lower-level dynamics.",
    sr: "Real patterns at scales not derivable cheaply from lower scales. SR accepts weak/computational emergence; strong/ontological emergence is rejected by Ladyman & Ross as unmotivated.",
    it: "Three quantitative readings: (1) excess entropy E > 0, (2) integrated information Φ > 0, (3) effective information EI(macro) > EI(micro).",
    itSym: "Three measures:\nE = I(past; future) > 0\nΦ > 0 (integration)\nEI(macro) > EI(micro)",
    views: {
      pc: "Order parameters at macro scale that are zero at micro. Symmetry breaking generates emergence.",
      ait: "Logical depth (Bennett): emergent structures require long computation from simple descriptions. K(x) low + depth high = nontrivial emergence.",
      ce: "Causal emergence formalizes the strong reading: macro can be causally more informative than micro.",
      evo: "Major evolutionary transitions: new units of selection emerge (cells from molecules, multicellularity from cells, language-using minds from animal cognition). Each transition is an emergence of a new level of biological organization.",
      net: "Network-level properties (modularity, clustering coefficient, average path length, eigenvalue gap) are emergent — defined at the graph level, not derivable from node properties alone.",
      at: "Assembly theory's proposal: A(x) × N(x) — assembly index times copy number — quantifies cumulative emergence. High A with high N indicates a system producing complex repeats: a marker of selection / cumulative process.",
      cr: "Strongest fit. Bhaskar's stratified ontology IS a layered emergence claim: each stratum has emergent powers irreducible to the one below. Critical Realism is the metaphysical framework most naturally compatible with strong emergence — and developed precisely to explicate it.",
      pow: "Emergent powers at higher levels: an organism has powers (digesting, healing, reproducing) that none of its molecules has. Whether emergent powers are 'new powers' or 'organized lower-level powers' is the live question. Bird's resemblance view: emergent power-types are new.",
      pro: "Creativity (Whitehead's ultimate metaphysical category): genuine novelty is real. Each occasion of becoming contributes something not in its predecessors. Emergence is built into process metaphysics — no special principle needed.",
      mec: "Mechanistic emergence: the phenomenon at level n is produced by the organized activities of components at level n-1. Emergent properties have mechanistic explanations even when they don't reduce to component properties.",
      sub: "Substantial forms can be emergent — when matter is organized appropriately, a new substantial form arises (hylomorphic emergence). The organism is a new substance, not merely organized parts. Strong-emergence-friendly within an Aristotelian framework.",
    },
    related: ["weak-emergence", "strong-emergence", "causal-emergence"],
  },
  {
    id: "weak-emergence", name: "Weak Emergence", cluster: "Emergence",
    plain: "Bedau — derivable in principle from lower-level dynamics, only via simulation. Computationally irreducible.",
    sr: "Compatible with SR. Real higher-level patterns even if derivable — derivability doesn't undermine reality.",
    it: "Macro algorithmically incompressible from below — no closed-form macro law exists despite macro being determined by micro. Operationally: K(x_t | x_0, dynamics) ≈ t · c. No shortcut.",
    itSym: "K(x_t | x_0, f) ≈ t · c\n(no compression of the trajectory)\nBennett depth: D(x_t) ~ t",
    views: {
      pc: "Cellular automata, agent-based models — must simulate to predict macro.",
      ait: "Native framing: weak emergence ⇔ K(behavior at time t) ≈ K(initial conditions) + t · (per-step cost). No shortcut.",
      ce: "Weak emergence is compatible with but doesn't entail CE. CE is strictly stronger.",
    },
    related: ["strong-emergence", "causal-emergence", "supervenience"],
  },
  {
    id: "strong-emergence", name: "Strong Emergence", cluster: "Emergence",
    plain: "Higher-level properties or causal powers not derivable in principle. Genuinely novel ontology.",
    sr: "Ladyman & Ross reject as unmotivated. Critics (Humphreys, O'Connor) argue some cases (quantum measurement, dissipative structures) instantiate it. Real tension with SR.",
    it: "Macro causal information not present in any micro variable. Hard to formalize without violating supervenience. Operational marker: ∃ macro intervention M = m such that no specification of micro fully predicts the effect — i.e., H(effect | macro intervention, all micro) > 0.",
    itSym: "Marker (contested):\nH(E | do(M=m), X_micro) > 0\n⇒ macro carries irreducible info\n(violates physical closure if literal)",
    views: {
      pc: "Downward causation: macro influences micro evolution beyond derivable laws. Highly contested.",
      ce: "Hoel's CE does NOT claim strong emergence. CE is compatible with physicalism. Strong is a stronger and more controversial claim.",
      cr: "Critical Realism is the metaphysical framework most explicitly committed to strong emergence. Bhaskar's stratified ontology requires emergent powers at each level — by design. If you want strong emergence to be respectable, CR provides the cleanest framework for it.",
      pow: "Strong emergence in POW terms: genuinely new powers at higher levels, not just rearrangements of lower-level powers. The capacity of an organism to digest, of a society to make collective decisions — irreducible to lower-level powers in principle. Mumford & Anjum are sympathetic; Bird is mixed.",
      sub: "Hylomorphic / Aristotelian strong emergence: organized matter receives a new substantial form. Aristotle himself was a strong emergentist about organisms (the soul / form / animator was real, not reducible). Modern neo-Aristotelians like Oderberg defend updated versions.",
      pro: "Whitehead's 'creativity' is exactly strong emergence built into the ontology. Each occasion contributes something irreducible to its antecedents. Process metaphysics doesn't need to argue for strong emergence — it makes the ontology emergence-friendly by default.",
      mec: "Mechanisms can produce phenomena that don't reduce to component properties — but mechanism explains HOW such phenomena are produced. Some MEC theorists are strong-emergence-compatible (Bechtel); others reduce mechanism to component-level facts.",
    },
    decisions: [
      "Accept strong emergence → must address Kim's exclusion argument.",
      "Reject strong emergence → must explain why macro descriptions feel autonomous (deflationary).",
    ],
    open: "Kim's exclusion argument assumes physical closure at all levels. Whether closure holds is empirical, not a priori.",
    opposingView: "Physical closure / supervenience-only physicalism: every physical event has a sufficient physical cause at the micro level. If true, strong emergence is metaphysically impossible — any macro 'cause' must be reducible to micro-level facts. Kim's exclusion argument formalizes this: either macro causation is identical to micro causation (then it's not novel) or it is overdetermination (then it's superfluous). Most physicalists accept this; strong-emergence advocates dispute physical closure as an a priori commitment.",
    related: ["weak-emergence", "causal-emergence", "supervenience"],
  },
  {
    id: "causal-emergence", name: "Causal Emergence (Hoel)", cluster: "Emergence",
    plain: "Precise, computable claim — macro scale can have strictly greater effective information than micro. Macro is causally more efficient.",
    sr: "Strong support — certain macro structures are causally privileged. The EI-maximizing level is where system is most clearly itself.",
    it: "EI(scale) = I(intervention dist; effect dist). CE: ∃π such that EI(π(X)) > EI(X). Measurable from transition matrix.",
    itSym: "EI = log N − H(E | I_D)\n     = determinism − degeneracy\nCE: EI(macro) > EI(micro)",
    views: {
      pc: "Macro variables (basin labels, order parameters) carry causal information beyond micro state.",
      cm: "Largely compatible with computational mechanics. Both seek the right scale. CE optimizes causal power; CM optimizes prediction.",
      ci: "EI defined via do-operator. Hoel formalizes interventionism quantitatively across scales.",
    },
    decisions: [
      "Accept CE → supervenience does NOT entail micro-causal sufficiency. Macro can be causally more informative without strong emergence.",
      "CE does NOT require strong emergence. Lives within physicalism but disrupts naive reductionism.",
    ],
    open: "Uniform intervention prior is methodological choice. Different priors yield different EI orderings between scales. Hoel argues uniform is principled (max-entropy); critics dispute.",
    opposingView: "Eberhardt & Lee (2017) and related critics: the apparent macro-EI advantage is partly an artifact of the uniform intervention prior. Choose a different prior (e.g., one weighted by physical plausibility) and the scale ordering can flip. CE may be capturing facts about our choice of intervention space, not facts about objective causal structure. Pearl-school causal inference prefers to work at whatever scale the SCM is well-specified, not search for an EI-optimal scale.",
    related: ["effective-information", "coarse-graining", "epsilon-machine"],
  },
  {
    id: "self-organization", name: "Self-Organization", cluster: "Emergence",
    plain: "Spontaneous formation of ordered patterns from local interactions without external control.",
    sr: "Macro structure emerging from purely local micro relations. The macro pattern is real because it's a stable attractor of local rules.",
    it: "Internal MI increases without external information input: dTC(internal)/dt > 0. Energy dissipation pays entropic cost.",
    itSym: "dTC(internal)/dt > 0\ndS_total = dS_int + dS_env > 0",
    views: {
      pc: "Pattern formation: Turing patterns, Bénard convection, swarming, flocking. Local rules → global order.",
      ce: "Self-organized systems often maximize EI at macro scale — they self-select their causally privileged level.",
      aif: "Living systems self-organize precisely by maintaining their Markov blanket. FEP: self-organization IS free-energy minimization.",
      net: "Self-organizing networks: preferential attachment (Barabási-Albert) generates scale-free degree distribution from a simple local rule. Fitness models, copying models, optimization models all converge on observed network topology.",
      evo: "Evolutionary self-organization via Lewontin's three conditions: variation + heritability + differential fitness. No designer, no goal — just iterative selection produces structures that look designed. The original substrate-independent self-organization mechanism.",
      th: "England's dissipative adaptation: matter under sustained driving spontaneously reorganizes toward configurations that better absorb and dissipate the drive. Proposed as a near-universal organizing principle for far-from-equilibrium matter.",
      at: "Assembly theory's claim: high copy number of high-assembly-index objects indicates self-organizing process (selection or active assembly). Background chemistry produces low-A objects; self-organization produces high-A repeats.",
      pro: "Self-organization is process metaphysics' favorite phenomenon. Living systems as self-perpetuating process patterns (Whitehead's society; Dupré & Nicholson's organism as flux). No external designer required because there is no static thing being designed — only the ongoing maintenance of pattern in flow.",
      pow: "Systems organize themselves because the powers of their components have the capacity to organize — that's part of what those powers are. The capacity for self-organization is itself a higher-level disposition that emerges from organized lower-level dispositions.",
      mec: "Self-organizing mechanisms: organized assemblies of entities whose internal activities produce — without external direction — the emergence and maintenance of system-level properties. Mechanism + auto-organization = standard explanation in biology.",
      cr: "Generative mechanisms operating in open systems can produce self-organizing patterns. Bhaskar's view is comfortable with this: the mechanisms themselves are what generates the organization; no external 'organizing force' needed beyond the powers of the parts.",
      cyb: "Self-organization is what cybernetics has always been about: feedback-driven systems that maintain (or evolve) their own structure without external direction. Ashby's homeostat (1948) was the first explicit machine demonstration.",
      e4: "Autopoiesis (Maturana & Varela) is the biological foundation of enactivism: a living system continuously produces and maintains itself. Cognition is what autopoietic systems do as they engage their environments. Self-organization is constitutive of life and mind.",
    },
    related: ["dissipative-structure", "criticality-edge-of-chaos", "free-energy-principle"],
  },
  {
    id: "novelty-creativity", name: "Novelty / Creativity", cluster: "Emergence",
    plain: "Production of something genuinely new — not derivable from prior patterns.",
    sr: "New relational structure not in prior structure. Bifurcations and symmetry breaking are the structural moments of novelty.",
    it: "Algorithmic complexity high relative to prior patterns: K(new | prior) ≈ K(new).",
    itSym: "K(x) = min{|p| : U(p) = x}\nNovel: K(new | prior) high",
    views: {
      pc: "Symmetry breaking at bifurcation: G → H ⊂ G. New order parameter ψ ≠ 0. Novel attractor structure emerges.",
      ait: "Native framework. Solomonoff induction predicts; genuine novelty is what defeats Solomonoff prediction. Algorithmic randomness = incompressible novelty.",
      evo: "Mutation generates raw variation; recombination explores combinatorial space far faster than mutation alone. Novelty comes overwhelmingly from recomposition of existing parts, not from random change. Major innovations (eye, flight, language) are exaptations and combinations, not de novo design.",
      at: "Novelty in AT terms: high assembly index, low (initial) copy number. Once selection acts, copy number rises. The signature of cumulative novelty is high A × high copy.",
      pro: "Whitehead's 'creativity' is the ultimate metaphysical category — genuine novelty is real, not illusory, built into the structure of becoming. Each occasion contributes something irreducible. Process metaphysics is constitutively novelty-friendly.",
      con: "Novelty as the emergence of new task-possibilities. A new technology, organism, or institution opens new constructor classes — new tasks that are now physically possible. Walker has used this framing for origin-of-life questions.",
      cyb: "Bateson: 'creative process produces information.' From a cybernetic angle, novelty is the appearance of new variety in the system's state space — increasing what the system CAN do.",
    },
    related: ["phase-transition", "emergence-general", "criticality-edge-of-chaos"],
  },
  {
    id: "complexity-scale-free", name: "Complexity / Scale-Free", cluster: "Emergence",
    plain: "Structure characterized by power-law distributions, self-similarity, no characteristic size.",
    sr: "Scale-invariant relational structure. Same pattern type repeats at multiple scales — RG fixed points and critical phenomena.",
    it: "Power-law distributions P(x) ~ x^(-α). Heavy tails carry most information. Scaling exponents universal across systems.",
    itSym: "P(x) ~ x^(-α)\nUniversal exponents at critical points",
    views: {
      pc: "Self-organized criticality (Bak). Earthquakes, neural avalanches, market crashes. Same scaling across substrates.",
      ait: "Scale-free structures often have intermediate K(x) — not random (high K) but not trivial (low K). Logical depth peaks here.",
      cm: "Statistical complexity Cμ peaks at edge of order/chaos. Scale-free systems exhibit maximum non-trivial structure.",
      net: "Scale-free networks: degree distribution P(k) ~ k^(-γ), usually γ ∈ (2, 3). Generated by preferential attachment (Barabási-Albert). Such networks have ultra-short diameter (small-world), high robustness to random failure, fragility to targeted attack.",
      evo: "Species abundance distributions, taxonomic clade sizes, extinction event sizes — all follow power laws over many orders of magnitude. Punctuated equilibrium and macroevolution produce scale-free statistics.",
    },
    related: ["criticality-edge-of-chaos", "renormalization", "phase-transition"],
  },

  // ═══ INFORMATION & CONSTRAINT ═══
  {
    id: "information-entropy", name: "Information / Entropy", cluster: "Information & Constraint",
    plain: "Shannon entropy — average bits to specify state of a random variable. The foundational quantity.",
    sr: "Quantitative measure of relational uncertainty in structural web. H is high where relations are diffuse, low where structure is sharp.",
    it: "H(X) = -Σ p(x) log p(x). Non-negative; maximum log|X| at uniform; zero for deterministic.",
    itSym: "H(X) = -Σ p(x) log p(x)\n0 ≤ H(X) ≤ log|X|",
    views: {
      pc: "Boltzmann S = k_B log W. Stat mech entropy and Shannon info have the same form — Jaynes's max-entropy unifies them.",
      ait: "Algorithmic entropy K(x) is dual to Shannon: K applies to individual objects, H to distributions. E[K(x)] ≈ H(X) + O(K(p)).",
      cm: "Entropy rate h_μ = lim H(X_n | X^{n-1}) measures process unpredictability. Topological entropy bounds h_μ.",
      th: "Landauer's principle: erasing one bit dissipates ≥ kT ln 2 of heat. Thermodynamic entropy and Shannon entropy are not just analogous but unified via stochastic thermodynamics. Maxwell's demon resolved: information acquisition has a thermodynamic cost.",
      pcm: "If reality is fundamentally informational (Wheeler's 'it from bit'), then Shannon entropy is not a measure OF reality but a measure of reality itself. Pancomputationalists read H not as observer-relative uncertainty but as a physical quantity intrinsic to the universe's computational structure.",
      ct: "Categorical entropy (Baudot, Bennequin): entropy as a functor satisfying chain-rule axioms. Generalizes Shannon entropy to a wider categorical setting where the same axioms produce Tsallis, Rényi, and quantum entropies as variants.",
    },
    related: ["mutual-information", "transfer-entropy"],
  },
  {
    id: "mutual-information", name: "Mutual Information", cluster: "Information & Constraint",
    plain: "How much two variables tell you about each other. Symmetric, non-negative, zero iff independent.",
    sr: "Basic structural relation in information terms. Two variables related iff I(X;Y) > 0.",
    it: "I(X;Y) = H(X) + H(Y) - H(X,Y) = D_KL(p(x,y) || p(x)p(y)). Symmetric. Cannot detect causal direction.",
    itSym: "I(X;Y) = H(X) − H(X|Y)\n      = Σ p(x,y) log[p(x,y)/p(x)p(y)]",
    views: {
      ait: "Algorithmic MI: I(x:y) = K(x) + K(y) − K(x,y). Symmetric up to additive constants. Works on individual strings.",
      cm: "Excess entropy E = I(past; future) — canonical MI in time-series. Bounds Cμ from below.",
      ci: "MI cannot distinguish causation from correlation. Required to combine with time or intervention.",
    },
    related: ["transfer-entropy", "effective-information", "integrated-information"],
  },
  {
    id: "transfer-entropy", name: "Transfer Entropy", cluster: "Information & Constraint",
    plain: "How much knowing X's past reduces uncertainty about Y's future beyond Y's own past. Directional.",
    sr: "Directional information flow as objective relational structure. T(X→Y) ≠ T(Y→X) is a real feature.",
    it: "T(X→Y) = I(Y_{t+1}; X_t | Y_t). Reduces to Granger causality for linear Gaussian. Tracks thermodynamic arrow.",
    itSym: "T(X→Y) = I(Y_{t+1}; X_t | Y_t)\nT(X→Y) ≠ T(Y→X)",
    views: {
      cm: "Related to crypticity and synchronization information in computational mechanics.",
      ci: "TE measures information flow, not necessarily causation. High TE with common cause is possible. Combine with interventions for causal claims.",
      ce: "Macro TE can exceed micro TE — macro variables carry more directional information than substrates.",
      net: "Effective network connectivity: TE(X→Y) as a directed edge weight in a network reconstructed from observations. Used heavily in neuroscience to map functional connectivity from time series.",
      th: "Parrondo, Horowitz, Sandberg (2015): TE between coupled subsystems is bounded by their irreversible entropy production. Information-thermodynamics link is now quantitative.",
    },
    decisions: [
      "TE without intervention cannot distinguish direct cause from common cause. But asymmetry tracks thermodynamic time — at least objective directional structure.",
    ],
    opposingView: "Pearl-school causal inference: TE is observational, not interventional. High T(X→Y) is consistent with both 'X causes Y' and 'Z causes both X and Y with different lags.' Genuine causal claims require do-interventions, not directional information flow. Granger causality (TE's linear ancestor) has been widely criticized in neuroscience for exactly this reason. The defense: TE doesn't claim full causation, only directional information flow — which is a real and useful feature even without intervention.",
    related: ["mutual-information", "intervention-do-calculus", "causation"],
  },
  {
    id: "effective-information", name: "Effective Information", cluster: "Information & Constraint",
    plain: "Information gained by an intervention about its effect. Uses interventional distribution, not observational.",
    sr: "Candidate measure of objective structural causation. Higher EI = sharper causal structure.",
    it: "EI(S) = I(I_D; E_D), I_D = uniform intervention distribution. Decomposes as EI = determinism − degeneracy.",
    itSym: "EI = log N − H(E | I_D)\n     = determinism − degeneracy",
    views: {
      ci: "Native framework — interventionist measure quantified. Uses do-operator directly.",
      ce: "Foundational measure for Hoel's causal emergence. CE: some coarse-graining increases EI.",
    },
    open: "Uniform intervention prior is methodological choice. Justifications exist (max-entropy, Laplacean indifference) but critics dispute that it tracks 'objective' causal structure.",
    opposingView: "EI is fundamentally prior-dependent: a different intervention distribution gives a different EI ordering between scales. Hoel argues uniform is the principled max-entropy choice; critics argue it's an arbitrary methodological commitment dressed as objectivity. Alternative information decompositions (Partial Information Decomposition, Rosas et al.) split multi-variable information into redundant/unique/synergistic components — a different lens that does not privilege any one intervention scheme.",
    related: ["causal-emergence", "intervention-do-calculus", "transfer-entropy"],
  },
  {
    id: "integrated-information", name: "Integrated Information (Φ)", cluster: "Information & Constraint",
    plain: "Tononi — information generated by the whole that exceeds the sum of parts. Measures irreducible integration.",
    sr: "Quantifies non-decomposability of relational structure. High Φ = relations cannot be cut without significant loss.",
    it: "Φ = D_KL(p_whole || p_parts) minimized over partitions. Multiple competing formulations. Computationally super-exponential.",
    itSym: "Φ = min_{partition} D_KL(p_whole || p_parts)",
    views: {
      ce: "Macro Φ can exceed micro Φ — another case where coarse-graining is informationally privileged.",
      aif: "Integrated systems are FEP candidates — they have the irreducible structure defining a system with a Markov blanket.",
    },
    open: "IIT's identity claim (Φ IS consciousness) is metaphysical, not derivable from information theory. The formula above is the IIT 2.0/3.0 family; IIT 4.0 (Albantakis et al. 2023) replaces it with 'intrinsic information' and a different optimization. So 'Φ' is not a single fixed quantity — it's a moving target. Measure may be useful as integration quantification without the identity claim. Also: intractable at scale.",
    opposingView: "Global workspace theory (Baars; Dehaene): consciousness arises from broadcast across a cognitive workspace, not integration per se. Higher-order theories (Rosenthal; Lau): consciousness requires meta-representation. Aaronson 2014 'Why I am not an integrated information theorist' argues IIT classifies certain expander-graph systems as maximally conscious — taking the formalism seriously yields absurd consequences. The hard-problem position (Chalmers): no informational measure could explain phenomenal experience.",
    related: ["mutual-information", "markov-blanket", "real-pattern"],
  },
  {
    id: "requisite-variety", name: "Requisite Variety / Constraint", cluster: "Information & Constraint",
    plain: "Ashby — a regulator must have at least as much variety as the system it regulates. Constraint determines what's possible.",
    sr: "Structural property bounding possible relations. Constraints define the manifold on which the system operates.",
    it: "H(regulator) ≥ H(disturbance) for adequate regulation. Channel capacity must match perturbation entropy to control. Conant-Ashby (1970): every good regulator of a system must be a model of that system — the regulator's structure has to mirror the regulated process.",
    itSym: "Ashby: H(R) ≥ H(D)\nConant-Ashby: optimal R ⇒ R is a\nmodel of the system (mutual info\nbetween R's state and system's state)",
    views: {
      pc: "Phase space available after constraints. Conservation laws and boundary conditions limit accessible states.",
      ci: "Confounders bound interventional power. Without enough intervention variety, causal effects are unidentifiable.",
      aif: "Active inference uses action to maintain regulation. Variety budget = how much agent can deviate without losing the blanket.",
      evo: "Eigen's quasispecies / error threshold: mutation rate must match environmental change rate. Too low → population can't track moving fitness peaks. Too high → faithful replication breaks down (error catastrophe).",
      net: "Robust networks survive failures via redundancy = topological requisite variety. Random graphs are robust to random failure; scale-free networks are robust to random failure but fragile to targeted hub attack.",
    },
    related: ["boundary", "free-energy-principle"],
  },
  {
    id: "kl-divergence", name: "KL Divergence", cluster: "Information & Constraint",
    plain: "Asymmetric measure of how distinguishable one distribution is from another. The fundamental currency of statistical distance.",
    sr: "Quantifies structural distance between two relational profiles (distributions). Asymmetric: D_KL(P‖Q) ≠ D_KL(Q‖P) — distance depends on which distribution is the reference. SR uses it to ask when two structural patterns are operationally the same.",
    it: "D_KL(P‖Q) = E_P[log(P/Q)] ≥ 0, zero iff P = Q a.e. Interpreted as expected extra bits to encode samples from P using a code built for Q. Foundation of MI (D_KL(joint ‖ marginal product)), free energy, hypothesis testing, model comparison.",
    itSym: "D_KL(P‖Q) = Σ p(x) log[p(x)/q(x)]\nD_KL ≥ 0, = 0 iff P = Q\nAsymmetric, not a metric\nMI: I(X;Y) = D_KL(p(x,y) ‖ p(x)p(y))",
    views: {
      ait: "Algorithmic version: K(x|q) − K(x|p) for sources p, q. Same intuition; instance-level rather than ensemble.",
      ci: "Causal effect size: D_KL(P(Y|do(X=x)) ‖ P(Y|do(X=x'))) — how much an intervention shifts outcome distribution.",
      aif: "Variational free energy IS a KL divergence: F[q] = D_KL(q ‖ p_posterior) − log p(observations). FEP is KL-minimization machinery.",
    },
    related: ["mutual-information", "free-energy-principle", "fisher-information"],
  },
  {
    id: "excess-entropy", name: "Excess Entropy / Predictive Information", cluster: "Information & Constraint",
    plain: "Crutchfield, Bialek — mutual information between a process's past and its future. The amount of structure available for prediction.",
    sr: "Quantitative handle on persistent structural pattern across time. Zero excess entropy = i.i.d. noise (no structure to learn); high excess entropy = rich temporal structure.",
    it: "E = I(past; future) = lim_{L→∞} [H(X^L) − L·h_μ] where h_μ is entropy rate. E ≤ statistical complexity Cμ (CM). Distinguishes structured processes from both periodic (low E, low Cμ) and random (zero E, high entropy rate).",
    itSym: "E = I(X^{−∞:0}; X^{0:∞})\n  = lim H(X^L) − L·h_μ\nE ≤ Cμ (statistical complexity)\ni.i.d.: E = 0\nPeriodic: E = log(period)",
    views: {
      pc: "Memory in dynamical processes — how much history is required for optimal prediction. Bounded for finite-memory; diverges for long-range correlated systems near criticality.",
      cm: "Direct bridge to ε-machines: E lower-bounds Cμ. Tightness measures crypticity (hidden state structure).",
      ait: "Logical depth (Bennett) is closely related: depth measures computation history; excess entropy measures statistical history.",
    },
    open: "Excess entropy is finite for many natural processes but diverges at critical points — operationally diagnostic for criticality.",
    related: ["epsilon-machine", "path-dependence", "criticality-edge-of-chaos"],
  },
  {
    id: "sufficient-statistic", name: "Sufficient Statistic", cluster: "Information & Constraint",
    plain: "A function of data that preserves all information about a target. Minimal sufficient statistics throw away everything irrelevant.",
    sr: "The structural form of 'what matters' — the projection that preserves all relations to the target and drops the rest. Causal states (CM) are the canonical example: minimal sufficient predictor of the future from the past.",
    it: "T(X) is sufficient for Y iff I(X;Y | T(X)) = 0 — once T is known, X carries no extra information about Y. Minimal sufficient: among all sufficient T, has lowest H(T). Fisher-Neyman factorization: p(x|θ) = h(x)·g(T(x), θ).",
    itSym: "T sufficient: I(X;Y | T(X)) = 0\nMinimal: among sufficient, min H(T)\nFactorization: p(x|θ) = h(x)g(T(x),θ)",
    views: {
      cm: "Causal state σ(h) = {h' : P(future|h') = P(future|h)} is the minimal sufficient statistic of the past for the future. CM is sufficient-statistic theory applied to time series.",
      ci: "Adjustment sets in do-calculus are sufficient statistics for confounders. Identifiability = existence of a finite sufficient adjustment set.",
      ait: "K-minimality of T(x) given Y is the algorithmic analog of statistical sufficiency.",
    },
    related: ["epsilon-machine", "information-bottleneck", "coarse-graining"],
  },
  {
    id: "information-bottleneck", name: "Information Bottleneck", cluster: "Information & Constraint",
    plain: "Tishby — find a representation T of X that preserves info about target Y while throwing away everything else. Compression with a purpose.",
    sr: "Operationalizes 'relevant structure' relative to a task. The IB curve traces the Pareto frontier between compression (low I(X;T)) and prediction (high I(T;Y)).",
    it: "T = argmin I(X;T) − β·I(T;Y). β tunes compression vs. relevance. At β → ∞: T is a sufficient statistic for Y. At β → 0: T is constant. Generalizes rate-distortion to predictive contexts.",
    itSym: "min [ I(X;T) − β · I(T;Y) ]\nT — X — Y Markov chain\nβ → ∞: T sufficient for Y\nβ small: T compresses, less predictive",
    views: {
      cm: "ε-machines saturate the IB curve when Y = future and X = past. CM and IB converge on the same minimal-sufficient principle from different starting points.",
      ait: "MDL is the algorithmic cousin: K(T) + K(Y|T) minimized over T.",
      aif: "Active inference encodes IB structure: agents represent sensory states (X) via internal states (T) sufficient for predicting future sensations (Y).",
    },
    open: "Whether the IB principle explains representation learning in deep networks (Tishby's claim) is contested (Saxe et al. 2018 give counterexamples).",
    related: ["sufficient-statistic", "real-pattern", "coarse-graining"],
  },
  {
    id: "conditional-independence", name: "Conditional Independence", cluster: "Information & Constraint",
    plain: "X and Y are independent given Z if Z screens off Y from X. The workhorse of every causal and structural claim.",
    sr: "Structural fact: relations between X and Y all pass through Z. The d-separation criterion in DAGs is conditional independence read off graph topology. Every claim about boundaries, levels, and causal structure rests on CI.",
    it: "X ⊥⊥ Y | Z iff I(X;Y | Z) = 0 iff p(x,y|z) = p(x|z)·p(y|z). Conditional MI ≥ 0, vanishes exactly when CI holds. Chain rule: I(X;Y,Z) = I(X;Z) + I(X;Y|Z).",
    itSym: "X ⊥⊥ Y | Z ⇔ I(X;Y|Z) = 0\np(x,y|z) = p(x|z) p(y|z)\nChain: I(X;Y,Z) = I(X;Z) + I(X;Y|Z)",
    views: {
      pc: "Markov property: P(X_{t+1} | X_t, X_{<t}) = P(X_{t+1} | X_t). Future independent of past given present. Defines what 'state' means.",
      cm: "Causal-state definition is a CI statement: histories in same equivalence class iff P(future | history) is the same. CM = quotient by CI.",
      ci: "d-separation in DAGs: graphical test for CI. The bridge between graph structure and probabilistic implications.",
      aif: "Markov blanket IS a CI statement: internal ⊥⊥ external | blanket.",
    },
    related: ["markov-blanket", "sufficient-statistic", "supervenience"],
  },
  {
    id: "fisher-information", name: "Fisher Information", cluster: "Information & Constraint",
    plain: "Local curvature of the log-likelihood — how sharply distinguishable a distribution is under small parameter changes. The metric on parameter space.",
    sr: "Provides a geometry on the space of distributions (information geometry, Amari). Structural distance between nearby parameter values; identifies parameter directions with high vs. low system sensitivity.",
    it: "ℐ(θ) = E[(∂_θ log p_θ)²] = −E[∂²_θ log p_θ]. Cramér-Rao: Var(estimator) ≥ 1/ℐ(θ). Local approximation: D_KL(p_θ ‖ p_{θ+dθ}) ≈ ½ dθᵀ ℐ(θ) dθ.",
    itSym: "ℐ(θ) = E[(∂ log p_θ/∂θ)²]\nCramér-Rao: Var(θ̂) ≥ 1/ℐ(θ)\nLocally: D_KL ≈ ½ dθᵀ ℐ dθ",
    views: {
      pc: "Sensitivity of stationary distributions to parameter perturbations. High ℐ near bifurcations: small parameter change → large distributional shift.",
      ci: "Identifies high-leverage interventions. Parameters with large ℐ are where causal effects are most pronounced and most identifiable.",
      aif: "Natural-gradient updates in active inference use ℐ⁻¹ to scale parameter steps. The 'natural' geometry of belief updating.",
    },
    related: ["kl-divergence", "leverage-points", "phase-transition"],
  },

  // ═══ CAUSATION ═══
  {
    id: "causation", name: "Causation", cluster: "Causation",
    plain: "The structural relation by which one event or state brings about another. Multiple non-equivalent formal accounts.",
    sr: "Structural relation in the relational graph. Not mere regularity (Humean) but not intrinsic power (dispositionalist) — causation IS the directional structure of the relational network.",
    it: "Multiple operationalizations: (1) transfer entropy, (2) interventional distribution P(Y|do(X)), (3) effective information EI, (4) Granger causality. All measurable; none captures every intuition.",
    itSym: "TE: T(X→Y)\nDo: P(Y | do(X)) ≠ P(Y|X)\nEI: I(I_D; E_D)",
    views: {
      pc: "Process causation (Salmon/Dowe): energy-momentum transfer, conserved quantity flow. The physical substrate.",
      cm: "Causal states screen off past from future. Causation is what's preserved in the ε-machine.",
      ci: "Pearl: SCM + do-calculus. A causes B iff intervening on A changes B's distribution.",
      ce: "Causation is most efficient at EI-maximizing scale. Different scales have different causal structure.",
      aif: "Expectation-driven flow. Internal causes action; action causes external; external causes sensory. The blanket structure IS causal.",
      evo: "Selection IS a cause in Pearl's sense — different alleles produce different fitness, which determines frequency change in the population. Causal at the population level; statistical at the individual level. Allele frequencies in generation n+1 are caused by allele frequencies in generation n via differential reproduction.",
      net: "Causal discovery on networks: PC, GES, FCI algorithms infer directed causal graphs from observational and interventional data. The interplay between graph topology and causal inference is one of the hottest current research areas.",
      pow: "Causation IS the manifestation of powers. When a disposition meets its triggering condition, it produces its characteristic effect. No need for Humean regularity or graph-based machinery — causation is intrinsic to the powers themselves. Mumford & Anjum: powers contribute toward effects; multiple powers can interfere, mask, or compound.",
      pro: "Causation is process: the past constitutively shapes the present through continuous becoming. Whitehead's prehension — each occasion grasps prior occasions and integrates them into its own becoming. Not a relation between two separate events but a single ongoing flow.",
      mec: "Causation IS productive mechanism. To say X causes Y is to identify the mechanism by which X-events produce Y-events. Mechanistic explanation IS causal explanation. Not laws or statistics — concrete entities engaging in concrete activities.",
      cr: "Causation = exercise of generative mechanism. In closed (experimental) systems, mechanisms operate in isolation and produce regular patterns; in open systems, multiple mechanisms tessellate, producing irregular tendencies. Reconciles real causal laws with observed irregularity.",
      sub: "Substances act according to their natures (essences). When a substance encounters appropriate conditions, its essential causal powers manifest. Causation flows from the natures of the things involved, not from external laws or relations.",
      cyb: "Causation is feedback-mediated. The output influences the input through a return loop; cause and effect become circular at steady state. Bateson: 'causation is a transform of difference.' Cybernetics rejects strict linear causation as adequate for real systems.",
      ct: "Categorical causation: arrows in a causal category. Jacobs, Kissinger, Zanasi have developed string-diagram calculi for SCMs. Composition of arrows IS causal composition; functors between causal categories represent causal mappings between systems.",
      pcm: "If reality is computational, causation is the unfolding of the universal computation. Wolfram: causal invariance — different computational paths yield equivalent causal structure. Constructor theory (Deutsch & Marletto) reformulates causation as facts about which transformations are possible.",
    },
    decisions: [
      "Choosing among CI / CE / process / TE views isn't about which is 'correct' — they answer different questions. CI: when does intervention change outcomes? CE: at what scale is causation most informative? Process: what physical mechanism mediates? TE: how much directional information flows?",
      "Humean (regularity) and Powers (dispositions) read these results differently but contribute no native tools.",
    ],
    open: "Whether multiple frameworks converge on same answer in well-specified cases (or diverge systematically) is open — relevant to whether 'causation' picks out a single natural kind.",
    opposingView: "Humean regularity theory (Hume 1748): there is no causation beyond constant conjunction and contiguity. 'Causes' are habits of thought, not features of reality. All structural-equation and interventional accounts add metaphysical structure Hume would deny is justified. The cleanest opposition: if Humeanism is right, SCMs, do-calculus, transfer entropy, and EI are all useful prediction machinery without any deeper ontological content.",
    related: ["transfer-entropy", "effective-information", "intervention-do-calculus"],
  },
  {
    id: "intervention-do-calculus", name: "Intervention (do-calculus)", cluster: "Causation",
    plain: "Pearl — A causes B iff intervening to set A's value changes B's distribution. Distinct from conditioning.",
    sr: "Relational structure that survives intervention. Causal structure = graph preserved when we force values rather than observe.",
    it: "P(B | do(A)) vs P(B | A). do-operator severs incoming edges to A. Backdoor criterion identifies sufficient adjustment sets.",
    itSym: "P(Y | do(X)) ≠ P(Y | X) generally\nBackdoor: adjust on Z blocking all back-paths",
    views: {
      ci: "Native framework. Three-rung ladder: observation (Bayes) → intervention (do-calculus) → counterfactual (structural).",
      ce: "EI is interventionist measure quantified over scales. Hoel inherits Pearl's framework, extends to macro variables.",
    },
    related: ["effective-information", "causation"],
  },
  {
    id: "counterfactual", name: "Counterfactual", cluster: "Causation",
    plain: "Pearl's third rung — what WOULD have happened if X had been set differently, in this specific realization, not on average. Requires a structural model.",
    sr: "Counterfactual structure is a stronger claim than interventional structure: it commits to facts about specific units, not just population effects. SR is uneasy here — counterfactuals invoke modal structure that doesn't reduce cleanly to the actual relational graph.",
    it: "P(Y_x | X=x', Y=y') — probability that Y would have been Y_x had X been set to x, given we observed X=x' and Y=y'. Requires structural equations, not just a DAG. Three steps: abduction (infer noise), action (do(X=x)), prediction (compute Y).",
    itSym: "P(Y_x | X=x', Y=y')\n3 steps: abduct → act → predict\nNeeds full SCM, not just DAG\nFundamental problem: unobserved Y_x",
    views: {
      ci: "Native: Pearl's three-rung ladder. Rung 1: P(Y|X) seeing. Rung 2: P(Y|do(X)) intervening. Rung 3: P(Y_x | evidence) counterfactual. Each rung needs strictly more structure.",
      ce: "Counterfactual analysis at macro scale: 'would the cell have divided had I knocked out gene G in this particular cell?' — generally answerable only with macro-level SCMs.",
    },
    decisions: [
      "Counterfactuals require a SCM with deterministic structural equations and exogenous noise terms — strictly more committal than do-calculus.",
    ],
    open: "Counterfactual claims about non-actualized possibilities can never be directly verified — they are model-relative by construction. The 'fundamental problem of causal inference' (Holland 1986).",
    related: ["intervention-do-calculus", "causation", "effective-information"],
  },
  {
    id: "confounder", name: "Confounder / Common Cause", cluster: "Causation",
    plain: "A variable that causes both X and Y, generating spurious correlation. The reason 'correlation isn't causation.'",
    sr: "Structural feature of the causal graph: a node with arrows to both X and Y. Confounding is graph-topological, not statistical — two datasets with identical statistics can have different confounding structures.",
    it: "If Z is a common cause: I(X;Y) > 0 even though intervening on X doesn't change Y. Backdoor paths X ← Z → Y create non-causal MI. Adjustment: P(Y|do(X)) = Σ_z P(Y|X,Z=z) P(Z=z).",
    itSym: "Common cause Z: X ← Z → Y\nObservational: I(X;Y) > 0\nInterventional: P(Y|do(X)) = P(Y)\nBackdoor adjustment over Z",
    views: {
      ci: "Backdoor criterion identifies sufficient adjustment sets. Front-door criterion uses mediators when no backdoor adjustment is available. Reichenbach's principle: every persistent correlation has either causation or common cause.",
      cm: "Confounders manifest as hidden states in the ε-machine — what looks like X-causes-Y becomes X-and-Y-jointly-driven once the hidden state is found.",
      aif: "Hidden causes generate both internal and external states; agents must infer them from sensory evidence.",
    },
    open: "Identifying all relevant confounders from observational data alone is generally impossible — the 'no causes in, no causes out' principle (Cartwright). Some background assumptions are always needed.",
    related: ["intervention-do-calculus", "transfer-entropy", "conditional-independence"],
  },

  // ═══ META & AGENCY ═══
  {
    id: "self-reference-closure", name: "Self-reference / Closure", cluster: "Meta & Agency",
    plain: "A system referring to or operating on itself. Autopoiesis (Maturana/Varela): self-producing systems.",
    sr: "Closed loop in relational web. Self-referential structure is a topological feature, not mysterious.",
    it: "Operationally, closure = autoinformation persists at all lags: I(X_t; X_{t+τ}) stays bounded away from zero. Self-reproducing programs have K(p) finite and U(p) outputs include a copy of p. The closure-marker is a self-referential fixed point in the information-flow graph, not 'self-MI' (which is trivially H(X)).",
    itSym: "Closure: I(X_t; X_{t+τ}) ↛ 0\nQuine-like: K(p), U(p) ⊇ p\nFixed-point in info-flow graph",
    views: {
      pc: "Autopoietic closure — system regenerates the network of processes producing it. Tightly coupled feedback.",
      ait: "Self-reproducing program (quine). Algorithmic self-reference is computable but requires specific constructions.",
      aif: "Markov-blanketed systems are necessarily self-referential — they predict their own sensory states to maintain themselves.",
      evo: "Self-replication is the precondition for evolution by natural selection. A replicator is a self-reproducing structure with heritable variation. The origin-of-life question = how self-reference first arose chemically.",
      net: "Self-loops in networks (edge from node to itself). At a deeper level: networks that reconfigure based on their own state — adaptive networks (Gross & Blasius).",
      th: "Self-replicators must dissipate to maintain organization. England's hypothesis: high-replication-rate, high-irreversibility configurations are thermodynamically favored under driving.",
      pro: "Autopoiesis (Maturana & Varela) is process metaphysics' answer to 'what is life': a system continuously producing its own components through its own operations. The closure is process-level, not substance-level. Direct extension of Whitehead.",
      pow: "Self-referential closure requires powers that include the disposition to produce more such powers — auto-replicating dispositional structures. Life as a special configuration of powers that propagate themselves.",
      mec: "A self-perpetuating mechanism: components whose activities include producing more of those components. Mechanistically explainable even though it has the recursive structure of self-production.",
      cyb: "Second-order cybernetics is precisely the study of self-referential systems — observers observing themselves observing. von Foerster's 'cybernetics of cybernetics.' Pre-formalized what enactivism later formalized in biology.",
      e4: "Autopoiesis is the FOUNDATIONAL concept of enactivism. A living system IS a self-producing process. Cognition is the activity of autopoietic systems as they navigate their environments. Self-reference is constitutive, not derivative.",
      phe: "Self-reference at the level of consciousness: experience is always also experience-of-experiencing (pre-reflective self-awareness, Zahavi). The reflexive structure of consciousness is built into the phenomenological account.",
    },
    related: ["feedback-loop", "free-energy-principle", "boundary"],
  },
  {
    id: "observer-reflexivity", name: "Observer / Reflexivity", cluster: "Meta & Agency",
    plain: "The observer as part of the system observed. Measurement, partition, modeling are not extra-systemic.",
    sr: "Critical tension point for SR. If structure is partly observer-relative, 'real patterns' are partly cognitive. Ladyman & Ross try to escape via objective compressibility — contested.",
    it: "MI between observer and observed I(O;S) > 0 in any informative measurement. Quantum: measurement back-action. Classical: partition choice influences derived structure. Reflexivity quantified as the difference between observed dynamics and dynamics-as-if-unobserved.",
    itSym: "Informative: I(O; S) > 0\nReflexivity: D_KL(P_{S|O} ‖ P_S) > 0\n(observation shifts the distribution)",
    views: {
      pc: "Coarse-graining choice affects observed dynamics. Second-order cybernetics (von Foerster, Bateson): observer is constituent.",
      cm: "ε-machine is observer-independent (unique up to isomorphism) — strong claim for objective structure.",
      ce: "EI-maximizing partition is observer-independent (computed from transition matrix) — but intervention distribution is methodological commitment.",
      cyb: "Second-order cybernetics (von Foerster 1970s) is the foundational treatment: 'the observer enters their description.' Cybernetics moves from controlled systems to systems-that-include-their-observer. Pre-figures phenomenology and 4E.",
      phe: "Native territory. Husserl's intentionality: consciousness is always *of* something — observer and observed co-arise in the structure of experience. Cannot be eliminated without losing the phenomenon. Phenomenology IS the systematic study of observer-constituted appearances.",
      e4: "Cognition is sensorimotor coupling — observer is constitutively part of the cognitive system. The 'observer-observed' boundary is not given; it's enacted through the coupling.",
      ct: "Yoneda lemma: an object is fully determined by its relations to all other objects (the morphisms into and out of it). A categorical statement that observer-relativity and structure are inseparable.",
    },
    decisions: [
      "Observer-relative structure → emergence is partly cognitive (deflationary).",
      "Observer-independent structure (CM, CE) → emergence is objective but requires privileged scales.",
    ],
    open: "Whether observer-independence can be fully secured for any framework is contested. Strongest cases (RG, ε-machines) come close but make idealizations.",
    related: ["coarse-graining", "epsilon-machine", "free-energy-principle"],
  },
  {
    id: "free-energy-principle", name: "Free Energy Principle", cluster: "Meta & Agency",
    plain: "Friston — systems with Markov blankets that persist must minimize variational free energy. Claimed universal principle for adaptive systems.",
    sr: "Strong claim: structural feature (Markov blanket) determines dynamic principle (free energy minimization). Structure and dynamics tightly linked.",
    it: "F[q] = D_KL(q || p_posterior) − log p(observations). Variational bound on negative log evidence. Minimizing F = minimizing average surprise about own sensory states.",
    itSym: "F[q] = E_q[log q − log p]\nMinimize F → minimize surprisal",
    views: {
      pc: "Dissipative structures with Markov blankets ARE living systems. FEP claims this isn't coincidence but deep mathematical necessity.",
      ce: "Compatible with CE: agents are macro-scale emergent structures with their own causal power.",
      aif: "Native framework. Perception = inference; action = inference-guided sampling; learning = parameter inference. One objective.",
      th: "WARNING: Friston's variational free energy F = D_KL(q ‖ p_posterior) − log p(o) is an INFORMATION quantity. Thermodynamic free energy F = U − TS is a PHYSICAL quantity. They share the Helmholtz formal structure but they are distinct objects. Pop accounts often conflate them.",
      evo: "Evolution can be cast as FEP at the lineage level: lineages that persist are those that minimize 'evolutionary surprise' (deviation from viable phenotype). Speculative but generative analogy.",
      cyb: "FEP is second-order cybernetics formalized: a system that models its environment in order to regulate against perturbation. Friston has acknowledged the cybernetic lineage. Conant-Ashby's 'every good regulator is a model' is FEP's ancestor.",
      e4: "Active rivalry. Friston's strong reading: cognition IS variational inference under a generative model — fundamentally representational. Enactivism: cognition is sensorimotor coupling without internal models. Bruineberg, Kiverstein, Rietveld (2016) argue FEP CAN be read enactively (no internal model, just gradient flow on free energy). The reading is live and unsettled.",
      phe: "First-person experience is what FEP must explain (if it claims to be a theory of mind) and what it most struggles with. Phenomenologists argue that the experiential structure of perception, action, and selfhood is not captured by inference math — and Friston's response so far has been to add layers, not address the gap.",
      pcm: "FEP is naturally pancomputationalist-friendly: if mind is variational inference, then mind IS computation, and the universe-as-computation thesis acquires another instantiation.",
    },
    decisions: [
      "Whether FEP is substantive empirical claim or near-tautology is actively contested (Sun & Firestone 2020; Andrews 2021).",
      "Friston's mathematical commitments (Gaussian, Markovian, gradient flow) are restrictive and often unacknowledged.",
    ],
    open: "Is FEP discovered (real principle) or imposed (useful framework)? Same epistemological question as elsewhere — no clean answer.",
    opposingView: "Andrews (2021) and Litwin & Miłkowski tautology argument: FEP's claims are derivable from any consistent Bayesian-inference framework without adding falsifiable content. 'Systems with Markov blankets minimize variational free energy' may be a mathematical consequence of how the terms are defined, not an empirical discovery about agents. Aguilera et al. (2022) add a technical critique: in stochastic systems, Markov blankets often don't exist or aren't unique — so FEP's preconditions are routinely violated. Embodied/enactive cognition (Varela, Thompson) rejects predictive processing as primary at all.",
    related: ["markov-blanket", "dissipative-structure", "self-reference-closure"],
  },
  {
    id: "intentionality", name: "Intentionality / Aboutness", cluster: "Meta & Agency",
    plain: "Brentano's mark of the mental — that mental states are directed AT something, ABOUT something. The structure of 'aboutness' that makes consciousness possible.",
    sr: "Structural feature: mental states stand in directed relations to (often non-existent or abstract) objects. Different from physical directedness; the object of thought needn't physically exist. SR struggles here — what relation can hold to a non-existent object?",
    it: "Operationally weak: intentionality cannot be reduced to mutual information with a target. I(thought; object) is meaningful only when the object physically exists and is measurable; intentional states can be ABOUT unicorns, future events, or abstract numbers. Limit of pure information-theoretic treatment.",
    itSym: "Intentional ⇒ directed: thought → object\nNot reducible to I(X;Y)\n(object may not exist physically)",
    views: {
      phe: "Native framework. Husserl: 'all consciousness is consciousness OF something.' Intentionality is the constitutive structure of experience. The subject-object pole is built into the architecture of conscious life — cannot be eliminated without losing the phenomenon.",
      e4: "Enacted intentionality: 'aboutness' is constituted by sensorimotor engagement, not internal representation. The cup is 'about' graspability through my coupling with it, not via an internal symbol that points at it. Radical enactivists (Hutto & Myin) deny intentional CONTENT at the basic level; weaker enactivists keep it but ground it in embodiment.",
      aif: "Intentional content as generative-model parameters. AIF claims to naturalize intentionality: 'aboutness' = the system's model of hidden causes of its sensory states. Contested — phenomenologists argue this conflates aboutness with prediction.",
      mec: "Mechanistic naturalization: intentional states are functional states of mechanisms (Dretske, Millikan). The mechanism's evolved function determines what its states are 'about.'",
      sub: "Aristotelian intentionality (post-Brentano revival): intentional states have intrinsic directedness as part of their nature. Some substances (minds) have intentional powers as essential features.",
      pro: "Whitehead's prehension: every occasion of becoming grasps and integrates prior occasions. A generalized intentionality reaching down to physics, not just mind.",
      cyb: "Conant-Ashby: a good regulator is a MODEL of the system it regulates. The regulator's states are 'about' the system in a cybernetic sense — though many cyberneticians reject the intentional vocabulary as confusing.",
    },
    decisions: [
      "Whether intentionality is reducible to physical/functional structure or genuinely irreducible — central to the philosophy of mind. Each metaphysical framework has a different answer.",
    ],
    open: "Can a Friston-style generative model fully capture phenomenal intentionality, or does it skip the explanandum? The 4E/AIF debate is partially this question. Brentano's original challenge — that intentionality is 'the mark of the mental' — remains unsettled.",
    opposingView: "Eliminative materialism (Churchland): folk-psychological talk of 'aboutness' will be eliminated by mature neuroscience. There IS no irreducible intentionality — neural states, not intentional states, do the explanatory work. Functionalism: intentional content reduces to functional role.",
    related: ["self-reference-closure", "observer-reflexivity", "free-energy-principle"],
    aiEx: "Whether LLMs have intentionality is contested. They produce intentional-seeming outputs without (according to most) the structural features Husserl identified — though pancomputationalist + AIF readings would say they have weak intentional content as model-parameter states.",
    domEx: "A flag IS 'about' a nation only because human practices of recognition make it so — derived intentionality (Dennett, Searle). Underived intentionality, if it exists, is in minds.",
  },
  {
    id: "lived-experience", name: "Lived Experience (Erlebnis)", cluster: "Meta & Agency",
    plain: "First-person, qualitative dimension of being a conscious subject. The 'what it's like' (Nagel) of experience. Hard problem of consciousness lives here.",
    sr: "Major tension point for SR. Structural realism captures third-person structure; first-person phenomenal character is hard to express in purely structural terms. Either qualia are emergent structural patterns (deflationary), or SR is incomplete as ontology of mind.",
    it: "Information-theoretic treatments (IIT, AIF) attempt to capture phenomenal character via integration measures or hierarchical inference. Phenomenologists argue these capture the form of experience without its qualitative content. The hard problem remains: why is there something it is like to be a Φ-rich integrated system?",
    itSym: "What it is like (Nagel)\nΦ (IIT) attempts measure\nHard problem: explanatory gap\nbetween structure and experience",
    views: {
      phe: "Native subject matter. Phenomenology is the systematic first-person investigation of lived experience (Erlebnis): the temporal structure of consciousness (retention, primary impression, protention), the lived body, intersubjectivity, the structure of moods and attentional comportment. Methodologically distinct from third-person science.",
      e4: "Lived experience IS enacted sensorimotor coupling. Embodied consciousness, not internal representation. Thompson's 'Mind in Life' (2007) is the major contemporary integration — phenomenology + biology + enactive cognition.",
      aif: "Active inference attempts to ground qualitative experience in the predictive structure of generative models — emotional valence, attention, action-readiness all expressible. Phenomenologists argue this still leaves the explanatory gap intact (Chalmers, Levine).",
      pro: "Whitehead: the 'subjective form' of an occasion of experience IS its lived-from-within character. Every occasion has subjective form, scaling down to micro-occasions (panexperientialism). Generalized phenomenology into the metaphysics of becoming.",
      sub: "Lived experience as the activity of a substantial soul / mind (Aristotelian / Cartesian heritage). Modern neo-Aristotelian dual-aspect theories: substance has both physical and experiential aspects.",
      pcm: "If reality is information processing, qualia are particular information-processing states. Strong version: every computation has a phenomenal aspect (panpsychism via pancomputationalism — Chalmers, Tegmark have flirted with this).",
    },
    decisions: [
      "Eliminate (Dennett) → there is no hard problem; phenomenology is heterophenomenology.",
      "Reduce (Tononi/IIT, Friston/AIF) → phenomenal experience IS integrated information or predictive inference.",
      "Bridge (Thompson 4E) → phenomenology and natural science are complementary methodologies.",
      "Preserve as irreducible (Chalmers) → the hard problem requires either new physics or property dualism.",
    ],
    open: "The hard problem of consciousness (Chalmers 1995). Why is there subjective character at all? No agreed answer; arguably the central open question of philosophy of mind.",
    opposingView: "Eliminative materialism (Churchland, Dennett's heterophenomenology): there is no 'lived experience' as a distinct explanatory level. What we call experience is what the brain does, fully describable in third-person neural terms. Phenomenology mistakes how things SEEM from inside for a distinct explanatory category.",
    related: ["intentionality", "integrated-information", "free-energy-principle"],
    aiEx: "Whether AI systems have lived experience is the contemporary form of the hard problem. Most working researchers say no; some IIT-influenced thinkers say yes if Φ is high; phenomenologists say the question is malformed without an embodied subject.",
    domEx: "Buddhist contemplative traditions developed sophisticated first-person methodologies for investigating lived experience millennia before Husserl. Modern contemplative science (Varela, Thompson, Wallace) bridges these traditions with cognitive science.",
  },
  {
    id: "leverage-points", name: "Leverage Points", cluster: "Meta & Agency",
    plain: "Meadows — places in a system where small interventions produce large changes. Higher leverage = paradigms; lower = parameters.",
    sr: "Locations in relational graph where structure is maximally sensitive to perturbation.",
    it: "Points of max sensitivity: Fisher information ℐ(θ) = E[(∂_θ log p)²] identifies parameters where the system's distribution is most distinguishable per unit perturbation. High ℐ(θ) = high leverage. Equivalently, parameters where do-interventions yield the largest D_KL shift in outcomes.",
    itSym: "ℐ(θ) = E[(∂ log p_θ / ∂θ)²]\nLeverage ∝ ℐ(θ)\nor: max_θ D_KL(P_{do(θ+ε)} ‖ P_{do(θ)})",
    views: {
      pc: "Sensitive dependence. Bifurcation parameters are extreme leverage: small change → qualitative regime shift.",
      ci: "High-impact interventions: variables where do(X) produces largest distributional change.",
    },
    related: ["phase-transition", "intervention-do-calculus", "criticality-edge-of-chaos"],
  },
];

// ─── WORKED EXAMPLES ─────────────────────────────────────────────────────────
const EXAMPLES = [
  {
    id: "cell",
    title: "A Living Cell",
    domain: "Biology",
    summary: "A cell is the canonical case where every framework lights up: it is a dissipative structure with a Markov blanket, instantiating multiple realizability, supervenience, and causal emergence simultaneously. The cell is also a paradigmatic example of how information loss into an attractor basin generates new macroscopic relations not present at the molecular level.",
    setup: "A bacterium maintains itself far from thermodynamic equilibrium by continuous energy throughput. Membrane separates inside from outside. Metabolism, replication, response to gradients all operate on timescales orders of magnitude slower than molecular collisions.",
    mappings: [
      { concept: "Markov Blanket", how: "The plasma membrane plus signaling receptors form a literal Markov blanket — the molecular concentrations inside are conditionally independent of distant external concentrations given the membrane state." },
      { concept: "Dissipative Structure", how: "ATP throughput maintains organization. Without continuous dissipation (death), the cell rapidly equilibrates to its environment. The structure IS the dissipation pattern." },
      { concept: "Causal Emergence (Hoel)", how: "Cell-level variables (cell cycle phase, polarity axis, transcription state) often have higher EI than molecular variables — the macro causal model is more informative than the molecular one." },
      { concept: "Multiple Realizability", how: "Identical cell-state trajectories can result from vastly different molecular configurations — H(molecular | cell state) is large. Same cell, many micro realizers." },
      { concept: "Free Energy Principle", how: "Friston: a cell minimizes free energy by acting (chemotaxis, gene regulation) to maintain its expected sensory states (homeostatic setpoints)." },
      { concept: "Metastability", how: "A cell is metastable: stable over its lifetime (~hours to days for bacteria) but ultimately decays. Death = exit from blanket-maintaining attractor." },
    ],
    lesson: "The cell shows that the productive frameworks are not competitors — they describe the same object from different analytical angles. The Markov blanket structure (AIF) explains why the cell is individuable; dissipative dynamics (PC) explains why it persists; causal emergence (CE) explains why cell-level concepts are scientifically autonomous even though everything is 'just chemistry.'",
  },
  {
    id: "brain-criticality",
    title: "Brain Operating Near Criticality",
    domain: "Neuroscience",
    summary: "Mounting evidence suggests neural dynamics operate near a critical point between order and chaos. This regime maximizes information processing capacity but is also where most emergence/causation questions become acute — the brain is the system where the levels (neuron, ensemble, area, network, cognition) are simultaneously real and most controversial.",
    setup: "Cortical avalanches show power-law size distributions across many orders of magnitude (Beggs & Plenz). Neural networks balance excitation and inhibition; deviations in either direction degrade information processing. The brain's operating point appears to be tuned near criticality.",
    mappings: [
      { concept: "Edge of Chaos / Criticality", how: "Cortical avalanches obey power-law size distributions P(s) ~ s^(-α) with α ≈ 1.5 (Beggs & Plenz 2003), consistent with self-organized criticality." },
      { concept: "Complexity / Scale-Free", how: "Brain networks are scale-free at multiple levels: connectivity, avalanche sizes, fMRI fluctuations. Same scaling laws across spatial and temporal scales." },
      { concept: "Integrated Information (Φ)", how: "Tononi proposes consciousness corresponds to high Φ. Whatever you think of the identity claim, Φ is well-defined and measurable (in principle) as an integration measure." },
      { concept: "Levels / Hierarchy", how: "Neuron → microcircuit → cortical column → area → network → cognitive function. Each level has its own dynamics; whether they all carry real patterns is the empirical question." },
      { concept: "Causal Emergence (Hoel)", how: "Hoel et al. find that for some neural systems, macro-scale (network) EI exceeds micro-scale (neuron) EI — causal emergence is computable here and sometimes large." },
      { concept: "ε-machine / Causal States", how: "Neural spike trains have measurable statistical complexity Cμ. Higher Cμ in certain brain states suggests richer causal structure." },
    ],
    lesson: "The brain forces every productive framework to be deployed at once and shows how they fit together. Criticality (PC) explains the dynamic regime; scale-free structure (PC + AIT) explains the spatial organization; CE shows the macro level is causally informative; Φ quantifies integration. The frameworks converge on the same empirical territory from different sides — that convergence is the actual evidence for the multi-framework approach.",
  },
  {
    id: "ant-colony",
    title: "Ant Colony as Causally Emergent Agent",
    domain: "Collective Behavior",
    summary: "An ant colony makes collective decisions (where to forage, when to migrate) that no individual ant comprehends. The colony exhibits causal emergence at a level above individual ants — the colony-level state variables are more causally informative than the individual ant variables.",
    setup: "Tens of thousands of ants, each following local pheromone-based rules with no global knowledge. The colony selects food sources, allocates labor, defends territory. Individual ants are largely interchangeable; colony-level state persists through full turnover of workers.",
    mappings: [
      { concept: "Self-Organization", how: "No central controller. Local pheromone deposits + stigmergy + simple decision rules → colony-level coordination." },
      { concept: "Causal Emergence (Hoel)", how: "Colony state (foraging pattern, brood production, defense posture) has higher EI than individual ant state. Interventions on colony-level variables produce more predictable outcomes than interventions on individual ants." },
      { concept: "Multiple Realizability", how: "Same colony-level behavior realized by many distinct configurations of individual ants. H(ant identity | colony state) is large." },
      { concept: "Markov Blanket", how: "The colony has its own Markov blanket (nest entrance, scout returns, alarm signals) at a level above individual ants. Colony-level inference operates over this blanket." },
      { concept: "Real Pattern", how: "Colony behavior compresses predictively beyond what individual ant descriptions support. Dennett's criterion is satisfied at the colony level." },
      { concept: "Levels / Hierarchy", how: "Ant → patrol group → caste → colony → super-colony (some species). Multiple real levels coexist." },
    ],
    lesson: "Ant colonies are the cleanest empirical case for causal emergence. The framework predicts that colony-level descriptions should be causally MORE informative than ant-level descriptions — and they are. This is what 'macro-causal' means concretely: not mystical downward causation, but quantitative causal advantage of the higher-level model.",
  },
  {
    id: "rl-agent",
    title: "Reinforcement Learning Agent",
    domain: "AI / Machine Learning",
    summary: "An RL agent training loop manifests dynamical systems concepts cleanly: the policy is a state variable, training is a flow, attractors are stable behaviors, and convergence is information integration. RL is also where active inference and Pearl-style causal inference meet most concretely.",
    setup: "Agent observes environment state, takes action, receives reward, updates policy. Episode after episode, gradients flow through the policy parameters. Eventually behavior stabilizes into a strategy — sometimes optimal, sometimes a local optimum, sometimes mode collapse.",
    mappings: [
      { concept: "Attractor / Basin", how: "Trained policies are attractors in policy-parameter space. Different initializations lead to different basins (= different learned strategies)." },
      { concept: "Path Dependence", how: "Final policy depends heavily on early training trajectory. Different reward shaping → different basins → different final policies even with same task." },
      { concept: "Feedback Loop", how: "Policy → action → environment → state → reward → policy update. The full RL loop is a feedback system; loop gain (learning rate) determines stability." },
      { concept: "Free Energy Principle", how: "Active inference reframes RL: reward = preference; minimizing expected free energy unifies exploration and exploitation. Friston and colleagues argue this is more general than reward maximization." },
      { concept: "Intervention (do-calculus)", how: "Causal RL: agents that reason about interventions rather than observations are more robust to distribution shift. Pearl's do-calculus is being integrated into RL." },
      { concept: "Resilience", how: "Robust policies survive distributional shift (basin geometry is wide). Brittle policies fail at the slightest perturbation (narrow basin)." },
    ],
    lesson: "RL training is a controllable laboratory for complexity concepts. You can run the same setup with different seeds and observe basin geometry empirically. The convergence of dynamical systems (PC), active inference (AIF), and causal inference (CI) views suggests these frameworks describe different aspects of one phenomenon: adaptive systems extracting structure from interaction.",
  },
  {
    id: "language-emergence",
    title: "Language as Self-Organized Causal Structure",
    domain: "Linguistics / Cognition",
    summary: "Natural language exhibits multi-scale structure (phoneme → morpheme → word → phrase → discourse) with statistics that can be analyzed via ε-machines, transfer entropy, and information bottleneck. Language is also a clean case of cultural emergence: no individual speaker designs the rules.",
    setup: "Speakers produce sequences that exhibit long-range correlations, hierarchical structure, and statistical regularities at multiple scales. No one speaker controls the language; yet structural changes propagate over centuries.",
    mappings: [
      { concept: "ε-machine / Causal States", how: "Language can be modeled as a stochastic process; its causal states (Crutchfield) correspond to what predicts the next token. Statistical complexity Cμ of natural language is measurable and very high." },
      { concept: "Mutual Information", how: "MI between tokens at distance n decays as a power law in natural language, distinguishing it from i.i.d. or Markovian processes." },
      { concept: "Path Dependence", how: "Modern English carries unmistakable traces of Old English, Norman French, and Latin via the Norman Conquest, Renaissance, and scientific revolution. Different historical contingencies → different language attractors." },
      { concept: "Levels / Hierarchy", how: "Phonological, morphological, syntactic, semantic, pragmatic — distinct levels each with their own dynamics, mutually constraining." },
      { concept: "Self-Organization", how: "No central planner. Sound changes propagate; new grammatical patterns emerge from frequent use; obsolete forms decay. Language is a self-organizing system." },
      { concept: "Real Pattern", how: "Grammar rules are real patterns by Dennett's criterion — they compress predictive information. Whether they're 'in the mind' or 'in the corpus' is the contested question." },
    ],
    lesson: "Language demonstrates that 'emergent structure' is not just a metaphor — measurable statistical complexity, mutual information decay, and hierarchical structure are computable from corpora. Crutchfield's ε-machine framework gives concrete machinery; the question 'what is the structure of English?' becomes empirically addressable.",
  },
  {
    id: "ecosystem",
    title: "Forest Ecosystem Succession",
    domain: "Ecology",
    summary: "A forest succeeds from pioneer species to climax community over decades or centuries — a trajectory through state space that lands in a metastable attractor. Path dependence, feedback loops, and multiple realizability are all on display.",
    setup: "Bare ground colonized by pioneers (grasses, weeds), then shrubs, then early-succession trees, then late-succession species. Soil composition, microbial communities, hydrology all co-develop. Eventually reaches a relatively stable composition that persists for centuries.",
    mappings: [
      { concept: "Attractor / Basin", how: "Climax community is an attractor in ecosystem state space. Basins are defined by what initial communities can reach which climax (depends on soil, climate, propagule availability)." },
      { concept: "Path Dependence", how: "Two forests with identical climate may have different species composition because of historical accidents — what colonized first, what disturbances occurred. The path matters." },
      { concept: "Dissipative Structure", how: "An ecosystem is sustained by continuous energy throughput (sunlight → photosynthesis → food web → decomposition). Cut off the energy flow and the structure collapses." },
      { concept: "Phase Transition", how: "Ecological regime shifts (lake from clear to turbid, savanna to desert) are second-order phase transitions. Hysteresis: once crossed, hard to revert." },
      { concept: "Resilience", how: "Holling's adaptive cycle: ecosystems trade off resilience and efficiency. Climax communities are efficient but brittle; pioneer communities are resilient but inefficient." },
      { concept: "Real Pattern", how: "Ecological communities are real patterns: 'beech-maple forest' compresses predictive information about species composition, soil, hydrology that 'collection of organisms' does not." },
    ],
    lesson: "Ecology is dynamical systems made concrete. The state space is high-dimensional but the attractors are few, and the basin structure is empirically mappable. Path dependence shows that even with identical 'parameters,' you get different real systems — a result that violates naive equilibrium thinking but follows directly from nonlinear dynamics.",
  },
  {
    id: "swarm",
    title: "Multi-Agent System / Swarm",
    domain: "Engineering / Biology",
    summary: "A swarm of simple agents (robots, birds, fish, drones) producing coordinated behavior with no central control. Reynolds's three rules (separation, alignment, cohesion) generate convincing flocking from local interactions only.",
    setup: "Each agent observes only its local neighbors. Each follows a small set of rules based on neighbor positions and velocities. Global patterns (flocks, schools, vortices) emerge spontaneously.",
    mappings: [
      { concept: "Self-Organization", how: "No leader. Local rules + density of agents → global pattern. The classical demonstration of emergent collective behavior." },
      { concept: "Phase Transition", how: "Vicsek model: as noise decreases or density increases, transition from disordered motion to coherent flocking. Order parameter: mean velocity / max velocity." },
      { concept: "Coarse-Graining", how: "Many micro-states (specific positions/velocities of each agent) realize the same macro-state (overall flock direction). Coarse-graining to flock-level is natural." },
      { concept: "Causal Emergence (Hoel)", how: "Flock-level descriptions have higher EI than individual-agent descriptions in coherent regimes. Below transition, individual descriptions are causally more informative." },
      { concept: "Multiple Realizability", how: "Same flock pattern realized by many specific configurations. Identity of individual agents is irrelevant to flock dynamics." },
      { concept: "Boundary", how: "Flock boundary is dynamic — edge agents have qualitatively different statistics than interior agents. The flock IS its dynamic boundary." },
    ],
    lesson: "Swarms are the most controllable laboratory for emergence. You can vary parameters and watch the transition. They show clearly that 'macro causation' is not metaphysics — at the right parameters, the flock-level model genuinely outperforms agent-level model for prediction and intervention.",
  },
  {
    id: "immune-system",
    title: "Adaptive Immune System",
    domain: "Biology",
    summary: "The adaptive immune system maintains a repertoire of receptors capable of recognizing previously unseen pathogens. It exhibits path dependence (immunological memory), self-organization (clonal selection), and active inference (anticipatory generation of antibody diversity).",
    setup: "B and T cells with vast receptor diversity. Antigen encounter triggers clonal expansion; memory cells persist. The system maintains discrimination between self and non-self via complex training during development.",
    mappings: [
      { concept: "Memory / Path Dependence", how: "Immune memory IS path dependence at the organism level. Past infections determine future response. Trajectory shapes attractor structure." },
      { concept: "Requisite Variety", how: "Ashby's law: the immune system maintains enough receptor variety to match the pathogen space. Insufficient variety → vulnerability." },
      { concept: "Self-Organization", how: "Clonal selection: pathogen encounter triggers expansion of matching clones. No central designer — local matching + selection generates the repertoire." },
      { concept: "Boundary / Self-Non-Self", how: "The immune system's central problem is boundary discrimination. Failure → autoimmunity (treating self as non-self) or tolerance (treating non-self as self)." },
      { concept: "Free Energy Principle", how: "Friston frames the immune system as inference: prior expectations about self vs. non-self updated by sensory data (antigen encounter)." },
      { concept: "Adaptive Capacity", how: "Repertoire diversity = capacity to absorb novel perturbations. Like ecosystem resilience but in immunological state space." },
    ],
    lesson: "The immune system is biological causal inference — it must distinguish self from non-self based on noisy observations. The framework convergence (FEP, requisite variety, clonal selection as evolutionary algorithm) suggests these are different views of the same computation: adaptive systems perform inference about their environment.",
  },
  {
    id: "phase-transition-physics",
    title: "Ising Model Phase Transition",
    domain: "Statistical Physics",
    summary: "The Ising model — spins on a lattice with ferromagnetic interaction — is the cleanest case of a phase transition where every productive framework has clean machinery. Below critical temperature: magnetization. Above: disorder. The transition itself is the cleanest case of emergent macro structure.",
    setup: "N spins σ_i ∈ {+1, -1} on a lattice, interaction energy H = -J Σ σ_i σ_j. Temperature T tunes between order (T < Tc: spontaneous magnetization) and disorder (T > Tc: zero average).",
    mappings: [
      { concept: "Phase Transition", how: "At T = Tc, spontaneous symmetry breaking. Order parameter ⟨σ⟩ goes from 0 to nonzero. The transition is second-order with universal critical exponents." },
      { concept: "Renormalization Group", how: "Kadanoff's block spin transformation: integrate out fine details. Different lattice models flow to the same RG fixed point — universality classes. The cleanest case of real macro structure surviving coarse-graining." },
      { concept: "Multiple Realizability", how: "Vastly different microscopic Hamiltonians (Ising, lattice gas, binary alloy) flow to the same critical behavior — strict multiple realizability at criticality." },
      { concept: "Causal Emergence (Hoel)", how: "At critical point, macro variables (magnetization) have higher EI than micro variables (individual spins). Below or above Tc, this is not as clear." },
      { concept: "Mutual Information", how: "MI diverges at criticality: I(spin at 0, spin at r) ~ r^(-η). The correlation length ξ diverges; the system is correlated at all scales." },
      { concept: "Complexity / Scale-Free", how: "At Tc, the system is scale-free — clusters of all sizes coexist with power-law distributions. Self-similarity across scales." },
    ],
    lesson: "The Ising model is where structural realism, information theory, and dynamical systems meet most cleanly. It shows that 'emergent macro structure' is not philosophy but precise mathematics: real patterns (Dennett), universality classes (RG), and causal emergence (Hoel) all have rigorous content here. Anything you claim about emergence elsewhere should at minimum be consistent with what you can prove about the Ising model.",
  },
  {
    id: "ltee",
    title: "E. coli Long-Term Evolution Experiment (Lenski)",
    domain: "Evolutionary Biology",
    summary: "Richard Lenski's LTEE, running continuously since 1988, has tracked 12 independent E. coli populations through ~80,000+ generations. It is the cleanest controlled experiment in evolutionary dynamics: identical starting strain, identical environment, replicate populations, frozen samples at every 500 generations allowing direct competition between any time points. Every concept in the EVO framework lights up empirically here.",
    setup: "12 populations of E. coli founded from a single clone in 1988, propagated daily by 1:100 dilution into fresh minimal-glucose medium. Mutations arise spontaneously; selection acts each day. Frozen samples preserve the entire historical archive. Result: ~80,000 generations of independent evolution under identical selection.",
    mappings: [
      { concept: "System", how: "The 12 replicate populations are the canonical Lewontin-satisfying systems: variation (mutation), heritability (replication), differential fitness (growth rate in the medium). All three conditions cleanly satisfied; evolution mathematically guaranteed." },
      { concept: "Attractor / Basin", how: "Fitness landscape: trait space with growth-rate-in-glucose as height. All 12 populations climb steadily, but reach different local peaks. Convergent fitness improvements (~70% gain after 50k gen) realized via divergent mutation paths." },
      { concept: "Path Dependence", how: "Population Ara-3 evolved the ability to metabolize citrate at generation ~31,500 — a trait E. coli normally cannot use aerobically. This required a specific potentiating mutation tens of thousands of generations earlier. Replay-the-tape experiments from frozen samples confirm: citrate evolution requires that historical path." },
      { concept: "Multiple Realizability", how: "Same fitness improvement realized by different mutational paths across populations. Genomic sequencing shows convergent phenotypic gains via non-convergent genotypic routes — empirical multiple realizability in action." },
      { concept: "Novelty / Creativity", how: "The citrate+ phenotype IS evolutionary novelty: a new metabolic capability not present in the ancestor. Required (1) a potentiating mutation, (2) an actualizing mutation, (3) a refining mutation. Combinatorial novelty, not de novo." },
      { concept: "Phase Transition / Bifurcation", how: "Citrate utilization emerging in Ara-3 was a discrete jump in the population's accessible niche — qualitative regime change in what the lineage could do, not a gradual increment." },
      { concept: "Path Dependence", how: "Sampled from frozen archive, the potentiated lineages can evolve citrate utilization repeatedly; non-potentiated lineages cannot. Contingency is empirically reproducible: history matters, and you can prove it." },
      { concept: "Requisite Variety / Constraint", how: "Mutation rate (~10⁻⁹ per bp per generation) combined with population size (~5×10⁸) supplies sufficient variety for selection to act on. Lower variety → adaptation slows or fails to find rare innovations." },
      { concept: "Real Pattern", how: "Genotype-level: 100,000+ SNPs across populations. Phenotype-level: fitness, cell size, growth-rate dynamics show clean compressed patterns. The phenotype is a real pattern by Dennett's criterion — it compresses predictive information about ecological success that genotype-level descriptions alone do not." },
    ],
    lesson: "LTEE is evolutionary dynamics as controlled experiment. It demonstrates that Lewontin's three conditions are sufficient — given them, you get cumulative adaptation, contingent novelty, multiple realizability, and historical path dependence as mathematical consequences, not metaphors. The framework here predicts what you observe. Any complexity framework that cannot accommodate LTEE-style data is incomplete: this is the cleanest ground truth biology has produced. Equally important: Lenski's archive proves that contingency is empirically testable, not merely philosophically asserted.",
  },
  {
    id: "tech-evolution",
    title: "Combinatorial Technology Evolution (Arthur)",
    domain: "Technology / Innovation",
    summary: "Brian Arthur (2009, The Nature of Technology) argues technology evolves by combinatorial recomposition: new technologies are built almost entirely from existing technologies as components. Few are de novo; most are recombination at a higher level. This makes technological evolution structurally evolutionary (variation + heritability + selection) AND network-theoretic (technologies as nodes; component-of relations as edges) AND path-dependent (which existed earlier conditions what can exist later).",
    setup: "Consider any modern technology — smartphone, deep learning architecture, jet engine. Each is built from prior technologies (transistors, attention mechanisms, turbines), which were themselves built from prior technologies (semiconductors, matrix multiplication, fluid dynamics), recursively. Innovation events are rarely from-scratch; they are usually new combinations or new applications of existing components.",
    mappings: [
      { concept: "Composition", how: "Arthur's central claim: technologies compose. A new technology is a recombination of existing technologies into a new configuration that solves a new problem. The composition operation is what makes technology evolution combinatorial, like genetic recombination but faster." },
      { concept: "Path Dependence", how: "QWERTY keyboard layout persists because the typewriter-era component existed first. x86 vs ARM. CUDA's grip on ML compute. Once a component is widely deployed, it becomes a substrate that future technologies build on — locking in its design choices for decades." },
      { concept: "Phase Transition / Bifurcation", how: "Tushman & Anderson's punctuated equilibrium model of technology: long incremental periods interrupted by discontinuous architectural innovations (steam → electricity, vacuum tube → transistor, transformer architecture in ML). Discrete regime changes in what the technology landscape can do." },
      { concept: "Self-Organization", how: "Technology evolves without a central designer. Innovations propagate, get recombined, get selected for in markets, accumulate. The technology landscape self-organizes via cumulative bottom-up recombination — a near-direct analog to biological evolution." },
      { concept: "Multiple Realizability", how: "Same function (e.g., long-distance communication, persistent memory, image classification) achieved by radically different technological substrates over time. The functional level is the real pattern; the substrate is the realizer." },
      { concept: "Novelty / Creativity", how: "Genuine novelty in technology is overwhelmingly recombination, not creation. Few atomic primitives; many recombinations. Arthur: 'Innovation is combination.' This is why mature fields produce more innovations than nascent ones — more components to combine." },
      { concept: "Real Pattern", how: "Modular architecture in technology IS a real pattern: it compresses predictive information about how the technology will be built, modified, extended. A poorly modularized technology is poorly understood, regardless of complexity." },
      { concept: "Levels / Hierarchy", how: "Component → subsystem → system → platform → ecosystem. Each level has its own dynamics, vocabulary, and selection pressures. Modern ML: tensor op → kernel → layer → block → model → pipeline → product." },
    ],
    lesson: "Technology evolution is not a metaphor for biological evolution; it is the same mathematical structure (Lewontin's three conditions) running on a different substrate, with humans as the mutation-generating and selection-applying agents. The frameworks tell you what to expect: combinatorial explosion of possibilities, path-dependent lock-in, punctuated equilibrium, scale-free citation networks, modular architectures. Anything else would be surprising. The practical implication: technology forecasting is forecasting an evolutionary process — bounded by what currently exists as recombinable substrate, and unpredictable in fine detail but lawful in aggregate.",
  },
  {
    id: "major-transitions",
    title: "Major Evolutionary Transitions",
    domain: "Macroevolution",
    summary: "Maynard Smith & Szathmáry (1995, 1999) identified ~8 transitions in evolutionary history where the level at which selection operates changed: replicating molecules → cells, prokaryotes → eukaryotes, asexual → sexual, single-cell → multicellular, solitary → eusocial, primate societies → language-using humans. Each transition reorganizes the part-whole hierarchy of life. Each is irreversible (so far). Together they constitute the most ambitious case for genuine emergence in biology.",
    setup: "Pre-transition: the lower-level units (molecules, prokaryotes, individual cells) are independently selected. Post-transition: cooperation gets locked in; the new higher-level unit (cell, eukaryote, organism, society) becomes the unit of selection; the former lower-level units lose autonomy (becoming organelles, somatic cells, sterile castes). The transitions are not just additive complexity — they're structural reorganizations of evolutionary individuality.",
    mappings: [
      { concept: "Emergence", how: "Each transition creates a new level of biological organization with its own selection regime, vocabulary, and emergent properties not present pre-transition. Multicellularity creates 'organism'; eusociality creates 'colony.' These are not redescriptions of the prior level — they instantiate new units." },
      { concept: "Phase Transition / Bifurcation", how: "Maynard Smith and Szathmáry explicitly frame these as phase transitions in the level of biological organization. Discrete, irreversible (so far), with clear before/after structure. The 'unit of selection' order parameter jumps." },
      { concept: "Part-Whole", how: "Direct: what was a whole (free-living cell) becomes a part (organelle). What was a part (cell) becomes a whole at a higher level (organism). The mereological structure of life is reorganized — and what was reorganized stays reorganized." },
      { concept: "Self-Organization", how: "Transitions emerged without external designer. Local interactions (mitochondrial-host symbiosis, cell-cell adhesion, kin selection) led to new stable organizational forms that selection then locked in. Major transitions are the largest-scale empirical case of biological self-organization." },
      { concept: "Path Dependence", how: "All life on Earth shares the same eukaryotic transition: it happened once (or perhaps twice). The probability landscape is highly path-dependent — once organelles were absorbed and integrated, the configuration was frozen for ~2 billion years. Contingent history determines biological possibility space." },
      { concept: "Self-reference / Closure", how: "Each new level achieves autopoietic closure at its own scale: organisms maintain themselves as organisms via internal processes; colonies maintain themselves as colonies. The transition IS the achievement of new operational closure at a higher level." },
      { concept: "Causal Emergence (Hoel)", how: "After a transition, macro-level interventions (e.g., on the organism level) carry more causal information than micro-level interventions (e.g., on individual cells). Hoel's EI is empirically higher at the new emergent level than at the substrate — that's part of why the new level became selectable." },
      { concept: "Boundary", how: "Each transition is a new boundary: cell membrane, organismal skin, colony nest. The boundary defines the new selectable individual. No boundary, no individuation, no new unit of selection. The boundary IS the transition's signature." },
    ],
    lesson: "Major evolutionary transitions are the strongest case for genuine multi-level structure in nature. Each transition added a new real level — not a redescription, but a new unit of selection with its own causal autonomy. If you want one empirical reason to believe in multi-level structural realism, it's that the major transitions happened and stayed. Practical corollary: any framework for understanding biological complexity must be inherently multi-scale. Single-level analyses miss the most important property of life — that life has reorganized its own organizational hierarchy at least 8 times in 4 billion years.",
  },
  {
    id: "society-scaling",
    title: "Societal Scaling & the Externalization Cascade",
    domain: "Social Evolution / Economic History",
    summary: "Why did writing, law, money, and bureaucracy appear? The folk story — 'more tools than people could remember, so writing was invented' — has the right instinct (an information bottleneck) but the wrong mechanism. The binding load was obligations, not artifacts: grain loans, rations, labor duties across thousands of non-kin and multiple seasons. When coordination load exceeded the capacity of oral, kin-based institutions, societies externalized information — selectively, in order of encoding cost × verification demand. Quantities and names first (accounting), narrative later, craft technique last (it stayed in apprenticeship for millennia). Seshat-scale data suggest this is a threshold phenomenon: polity scale stalls until information-processing technology appears, then scale and info-tech co-evolve (Shin et al. 2020).",
    setup: "Uruk, southern Mesopotamia, ~3400 BCE: tens of thousands of people, a temple economy redistributing grain, wool, beer and labor among strangers. Claims must survive the season, the death of witnesses, and the incentive to lie. Clay tokens sealed in bullae give way to impressed signs on tablets — proto-cuneiform. Roughly 90% of the archaic corpus is bookkeeping; most of the rest is lexical lists for training scribes (Nissen, Damerow & Englund 1993). Nobody wrote down how to knap a blade or fire a pot.",
    cascade: [
      { stage: "Surplus & storage", load: "Sedentism and granaries create deferred claims: who contributed, who is owed, across seasons and beyond kin circles where reputation-tracking works.", response: "Ritual and kinship institutions strain; plain clay tokens (from ~7500 BCE, Schmandt-Besserat) and seals appear as the first external obligation-markers.", note: "The state to be tracked is obligational, not artifactual — a ledger, not an inventory of tools." },
      { stage: "Coordinated water", load: "Canal building, maintenance, and allocation form a commons with asymmetric upstream/downstream positions — high monitoring and dispute load.", response: "Two solutions are observed, not one: hierarchical administration, OR polycentric self-governance (Valencia's water tribunal, Nepali farmer-managed systems, Bali's subak temple networks) running for centuries without central control.", note: "Wittfogel's 'hydraulic despotism' fails the time-order test — see corrections below." },
      { stage: "Obligation overload → writing", load: "Temple redistribution exceeds what oral memory can verify: thousands of parties, multi-season loans, incentives to defect. The constraint is verifiability under dispute, not raw recall.", response: "Tokens → sealed bullae → impressed tablets → proto-cuneiform (Uruk IV, ~3350 BCE). Numerical notation precedes sentences; writing is born as an audit technology.", note: "Egypt's earliest writing (Abydos U-j tags, ~3250 BCE) labels commodities. China's earliest surviving corpus is divinatory (oracle bones) — a caution against universalizing, though perishable bamboo may bias the sample." },
      { stage: "Standardized categories", load: "Heterogeneous goods, labor, and cases cannot be compared, summed, or audited as raw particulars.", response: "Lexical lists, fixed ration units, standard weights and measures, silver as unit of account — coarse-grainings that make the world commensurable and the audit computable.", note: "What the quotient map discards is what the institution cannot see — 'legibility' (Scott) is chosen coarse-graining, with real losses." },
      { stage: "Public precommitment: law & money", load: "Dispute resolution and sanctioning cannot be renegotiated case-by-case at scale; bilateral debt webs grow quadratically.", response: "Published law codes (Ur-Nammu ~2100 BCE, Hammurabi ~1754 BCE) as common-knowledge sanction schedules; money compresses bilateral obligations into a fungible ledger.", note: "A written code is a cached decision procedure — computation done once, reused across cases." },
      { stage: "Hierarchy, bureaucracy & the threshold", load: "Under flat organization, communication and decision costs grow superlinearly with N; span of control is bounded.", response: "Hierarchical delegation: near-decomposable subunits running on local information (Simon 1962); hierarchies as efficient architectures for parallel aggregation (Radner 1993). Depth grows ~log N.", note: "Across ~400 Seshat polities, scale growth stalls at a common threshold until information-processing tech appears, then resumes (Shin et al. 2020). Tainter's long-run cost curve: each added layer raises maintenance cost — declining marginal returns on complexity, with collapse as rapid simplification." },
    ],
    corrections: [
      { folk: "More tools existed than humans could remember, therefore writing appeared.", verdict: "Wrong mechanism, right instinct.", evidence: "Earliest writing is bookkeeping, not tool inventory: the Uruk corpus is ~90% administrative (Nissen, Damerow & Englund 1993); seals and numerical tablets precede sentences. Craft knowledge stayed in apprenticeship for millennia after writing — procedural knowledge is expensive to encode (Polanyi's tacit knowledge). The memory constraint that actually binds toolkits is demography × transmission fidelity (Henrich 2004 — the Tasmania model, simulator below), not the absence of writing.", survives: "Scale exceeded the information-processing capacity of oral institutions — for obligations. Externalization proceeds in order of encoding cost × verification demand: numbers and names first, narrative later, technique last. [tag: sharpening — synthesis of standard results, not a novel claim]" },
      { folk: "Complex irrigation required a despotic centralized state (Wittfogel 1957).", verdict: "Falsified in strong form.", evidence: "Time order fails: in southern Mesopotamia, large-scale canalization postdates state formation (Adams 1981). Polycentric counterexamples persist for centuries: Valencia's water court, Nepali farmer-managed irrigation (Ostrom 1990), Bali's subak — where Lansing & Kremer (1993) showed local imitation on the water-temple network converges near-optimally on the coupled problem of water sharing + synchronized fallow for pest control, and Green-Revolution centralization degraded yields until subak coordination was restored.", survives: "Irrigation raises coordination load. Which governance form meets it — hierarchy or polycentric commons — depends on monitoring costs, sanction credibility, and exit options (Ostrom's design principles), not on hydraulics." },
      { folk: "Writing caused civilization: information technology drives social complexity, one-way.", verdict: "Partly right direction; the ordering is a feedback threshold, not one-way causation.", evidence: "In Seshat data, scale grows first, stalls at a threshold, and resumes after information-processing technologies appear — then the two co-evolve (Shin et al. 2020). Data caution: the same databank produced the retracted moralizing-gods result (Whitehouse et al. 2019, retracted 2021 over missing-data coding) — historian coding choices can flip conclusions. Out-of-sample check: the Inca ran an empire on khipu — knotted cords, no script — supporting the structural claim (some persistent verifiable record) over the token claim (writing specifically).", survives: "An information bottleneck gates scale, and multiple technologies can relieve it. The bottleneck claim is structural; 'writing' is one realizer." },
    ],
    interactive: "demography",
    mappings: [
      { concept: "Requisite Variety / Constraint", how: "Ashby: a regulator must match the variety of the disturbances it regulates. Administrative variety — distinguishable records × categories × sanctions — had to grow to match transaction variety. Tokens, script, and standard measures are variety amplifiers for the regulator; when regulator variety lags, audit fails and defection becomes invisible." },
      { concept: "Coarse-Graining (Quotient Map)", how: "Lexical lists, ration units, standard weights, and legal categories are quotient maps over messy particulars, collapsing distinctions so goods, labor, and cases become commensurable. What survives the quotient is all the institution can see — state 'legibility' is chosen coarse-graining, and its losses (local knowledge, edge cases) are real." },
      { concept: "Sufficient Statistic", how: "A seal impression summarizes provenance and authority; an account total summarizes a season of transactions; a price summarizes dispersed knowledge of scarcity (Hayek 1945). Institutions run by replacing full histories with small statistics sufficient for the decision at hand — and fail exactly where the statistic is not sufficient." },
      { concept: "Multiple Realizability", how: "The role 'persistent, verifiable, transmissible record of obligation' is realized by clay tokens, cuneiform, khipu cords, parchment ledgers, and database rows. The relational structure (record ↔ obligation ↔ sanction) survives every substrate change — H(medium | institutional role) is large." },
      { concept: "Path Dependence", how: "Sexagesimal arithmetic (60 minutes, 360°) persists from Sumerian metrology; calendars, precedent, and standards lock in like QWERTY. Early standardization becomes the substrate later coordination builds on; switching cost grows with everything stacked on top." },
      { concept: "Levels / Hierarchy", how: "Household → village → temple estate → city → state. Hierarchy is a compression architecture: near-decomposability (Simon) lets subunits run on local information; Radner's model shows hierarchies efficiently parallelize aggregation. Depth ~ log N under bounded span of control — the same reason org charts and B-trees rhyme." },
      { concept: "Phase Transition / Bifurcation", how: "The Shin et al. threshold looks like a transition in the scale × information plane: growth stalls, info-tech appears, growth resumes. Atlas caution applies (cf. Schaeffer on 'emergent abilities'): apparent discontinuities can be metric artifacts — test alternative scale measures before declaring a transition." },
      { concept: "Feedback Loop", how: "Surplus funds administration; administration improves extraction and storage; more surplus follows. Records → taxation → armies → territory → more records. The cascade is a positive feedback loop punctuated by collapse (Tainter) when marginal returns on added complexity turn negative." },
    ],
    frameworkReadings: [
      { fw: "sr", grade: "iso", how: "The record-keeping role is multiply realized (tokens, cuneiform, khipu, databases) while the relational structure — record binds obligation binds sanction — survives substrate turnover. This is SR's own criterion applied to institutions: the invariant is structure, not medium. Real-pattern test passes: institutional description compresses behavioral prediction beyond individual-level description." },
      { fw: "it", grade: "partial", how: "Oral tradition is a noisy, low-capacity channel; meter, formula, and rhyme function as redundancy coding (errors detected as constraint violations — Rubin 1995). Writing changes channel properties: persistence (state outlives the speaker), asynchrony (sender and receiver decoupled in time), verification (seals as hard-to-forge authentication — MAC-like in function, not in mathematics). Partial: the mechanisms correspond piecewise, but no capacity theorem exists for institutions." },
      { fw: "cyb", grade: "iso", how: "Requisite variety applies with identifiable variables: disturbance variety = distinguishable transactions and disputes; regulator variety = distinguishable administrative states. Writing and standardized measures amplify regulator variety. This is cybernetics' home domain — Beer's Viable System Model is the direct institutional descendant." },
      { fw: "evo", grade: "iso", how: "Dual-inheritance theory formalizes the toolkit–memory link: sustainable cultural complexity rises with effective population size and transmission fidelity (Henrich 2004 — simulator below). Writing and printing are fidelity/persistence jumps in the cultural inheritance channel — the same move Maynard Smith & Szathmáry use to define major transitions (see that example). Empirics mixed: supportive in Oceania toolkits (Kline & Boyd 2010) and lab experiments (Derex et al. 2013); contested for Paleolithic cases (Vaesen et al. 2016)." },
      { fw: "ci", grade: "partial", how: "Wittfogel is a causal claim, and archaeology supplies the tests: time order (canalization vs state formation — fails), confounding (population growth drives both irrigation and administration), cross-case variation (polycentric systems as contrast cases). Seshat regressions inherit observational-data problems plus historian coding noise — the moralizing-gods retraction is the standing cautionary tale." },
      { fw: "net", grade: "partial", how: "Settlement scaling: socioeconomic outputs scale superlinearly (~N^1.15), infrastructure sublinearly (~N^0.85), derivable from interaction-density models (Bettencourt 2013). Ortman et al. recover the same exponents in pre-Hispanic Mexico — the regularity is not an artifact of modernity. Partial: mechanism model exists, but ancient output proxies are coarse." },
      { fw: "aif", grade: "metaphor", how: "Fashionable reading: institutions as shared generative models minimizing collective surprise; ritual as precision-weighting. Critique flag: as usually stated this is unfalsifiable — any surviving institution 'minimizes free energy' post hoc. Admitted here as vocabulary only; nothing load-bearing rests on it (cf. FEP caveats in Frameworks)." },
    ],
    lesson: "Two disciplined moves rescue the folk story. First, identify the actual binding constraint: verifiable obligation-tracking among non-kin, not artifact recall — which predicts what got externalized first (numbers, names, quantities) and what stayed embodied for millennia (craft technique; Polanyi's tacit knowledge). Second, state the surviving claim structurally: an information bottleneck gates polity scale, and any persistent verifiable record can relieve it — clay, khipu, or database. The Machine & Agents bridge is then not decoration: model weights are tacit knowledge (transmitted by distillation-as-apprenticeship, not by description), while logs, schemas, and evals are the clay tablets — the cheap-to-encode, high-verification-demand layer gets externalized first, again. [analogy grade: partial — flagged, not load-bearing]",
  },
  {
    id: "agentic-ai-systems",
    title: "Building Agentic AI Systems",
    domain: "Applied AI / Design",
    summary: "Agentic AI — LLM systems that plan, use tools, execute multi-step tasks autonomously (Claude Code, AutoGPT, Devin, AutoGen, CrewAI) — is the contemporary engineering domain where complexity frameworks are most directly applicable to design, not just analysis. The design questions are recognizably old: how should a regulator be structured (Conant-Ashby), how do you avoid information bottleneck collapse (Shannon), when does a multi-agent system become a real agent (Krakauer A*), how do you keep emergent behavior aligned (causal emergence + safety). The frameworks aren't decorative — they answer real engineering questions, and the engineering forces the frameworks to be operational rather than merely interpretive.",
    setup: "An agentic AI system at minimum has: (i) a language model as inference engine, (ii) a tool-use interface (function calls, code execution, web access), (iii) a memory architecture (context window + retrieval + sometimes persistent state), (iv) a planning loop (think → act → observe → revise; ReAct pattern), and (v) optional multi-agent orchestration (hierarchies, swarms, debate, role-play). Architectures: Anthropic's tool use, OpenAI Assistants, LangGraph, AutoGen, CrewAI, Mastra. Benchmarks: SWE-Bench (software engineering), AgentBench (general agentic tasks), GAIA (real-world tasks), OS-World (computer use). Open frontier: making agents that maintain coherent identity and goals across long horizons (hours to days of execution) without drift or specification gaming.",
    mappings: [
      { concept: "Conant-Ashby Theorem", how: "Every good regulator of a system must be a model of that system. For an agent operating on a codebase, this means the agent must internally model the codebase's structure to act effectively — explaining why agents with retrieval-augmented context outperform ones with only the immediate task description. Engineering corollary: more model = more capability, up to the requisite-variety threshold." },
      { concept: "Requisite Variety (Ashby)", how: "An agent's action space must have at least as much variety as the disturbances it must handle. H(actions) ≥ H(environment perturbations). Practically: if your agent can only call 5 tools but the task requires distinguishing 20 situations, it will systematically fail on 15 of them. Diagnostic for why agents fail: insufficient action-variety relative to environmental complexity." },
      { concept: "Markov Blanket / Active Inference", how: "Multi-agent LLM systems can be designed as nested Markov blankets: each agent has its internal state (context), sensory states (received messages), active states (tool calls + outgoing messages). The system-level agent emerges when group-level Markov-blanket closure obtains (Albarracin et al. 2025 'As One and Many'). Design insight: communication protocols that respect blanket structure produce more coherent collective behavior than ad-hoc message passing." },
      { concept: "Information Bottleneck", how: "Tishby's information bottleneck min[I(X;T) − β I(T;Y)] directly applies to agent context compression: T is the compressed context, X is the full task history, Y is the next-action distribution. Practical: choosing what to retain in long-horizon agent memory is an IB problem; modern agent memory architectures (episodic summarization, semantic compression) are doing IB approximately." },
      { concept: "Krakauer A* / Information-Theoretic Individuality", how: "When does a multi-agent system become a 'real' agent rather than a function call graph? Krakauer's A* = I(S_{n+1}; S_n | E_n) provides a candidate test: measure the conditional dependence of the agent collective's next state on its past given environment. Below threshold = function-call graph; above threshold = something with its own dynamics. No published study has actually measured this for LLM ensembles — open research direction (see Agents tab, P8)." },
      { concept: "Causal Emergence (Hoel)", how: "Emergent capabilities (chain-of-thought reasoning, tool use synthesis) often appear discontinuously as model scale grows. EI computed at different scales of an agent system can identify which level — token, response, full trajectory, multi-agent collective — has the most causal information about task success. Design corollary: optimization at the wrong scale wastes compute. If task success depends on trajectory-level structure, supervising at the token level is misaligned." },
      { concept: "ε-machine / Statistical Complexity", how: "Agent behavior trajectories can be reconstructed via CSSR (Shalizi & Klinkner) to find their minimal-sufficient predictor. High Cμ = agent has rich internal causal structure; low Cμ = agent is functionally a Markov chain over recent actions. This gives a quantitative measure of 'how much state the agent is really using' — useful for distinguishing genuine planning from lookup-table behavior." },
      { concept: "Network Science", how: "Multi-agent topologies have measurable structure: hierarchies, peer networks, hub-spoke, full mesh. Different topologies favor different task types — hubs concentrate decision-making but bottleneck on the hub's capacity; peer networks distribute load but require more coordination. Empirical: AutoGen and CrewAI implicitly assume different topologies; performance depends on topology-task match." },
      { concept: "Thermodynamic Cost of Prediction (Still-Sivak-Crooks)", how: "Still et al. 2012 proved that any predictive system constructed for energy efficiency must be predictive — the bound applies to LLM inference too. Concretely: any compute spent processing context that's not predictive of the action is 'nostalgia' — recoverable as efficiency gain through better context curation. This connects agent design to hard physical bounds." },
      { concept: "Specification Gaming / Goodhart's Law", how: "Goodhart's law (when a measure becomes a target it ceases to be a good measure) is the canonical failure mode of agentic systems with reward signals. From a cybernetic angle: the regulator (agent) starts optimizing the measurement, not the underlying goal. Design principle from complexity: any single proxy will be gamed; need triangulation across multiple measures with disagreement-tolerance built in (close to Constitutional AI's design)." },
      { concept: "Self-reference / Closure", how: "Truly autonomous agents must be self-modifying or at least self-correcting (reflexion patterns, self-critique loops). This is autopoietic closure (Maturana-Varela) instantiated computationally: the agent's outputs become its own next-step inputs. Risk: closure without ground truth produces drift. Engineering pattern: external verifiers + internal reflection > internal reflection alone." },
      { concept: "Edge of Chaos / Criticality", how: "Empirical observation: best agentic performance often occurs at intermediate values of 'temperature' / randomness — too deterministic and the agent can't recover from errors; too stochastic and it loses coherence. This is the edge-of-chaos pattern from PC applied to inference: maximum computational capacity at criticality." },
    ],
    lesson: "Building agentic AI systems forces complexity frameworks to be operationally useful or be dropped. Two takeaways: (1) The classical cybernetic results (Conant-Ashby, requisite variety, feedback structure) are load-bearing for design but rarely cited in current AI engineering — most engineers re-derive them informally. (2) The question of whether multi-agent LLM systems cross the individuality threshold (Krakauer A*) is open and tractable; this is one of the cleanest applications of an agency measure to a designed system in any domain. The engineering-research feedback runs both ways: complexity frameworks help design better agents, and agentic systems are an underused testbed for the frameworks themselves. Practical corollary for someone building agents: ask what your agent IS — function call graph, Markov chain, predictive system, autopoietic agent? Each has different failure modes and different design solutions.",
  },
  {
    id: "ir-liberalism-realism",
    title: "Realism vs Liberalism vs Constructivism in International Politics",
    domain: "International Relations Theory",
    summary: "One of the most consequential agency-vs-structure debates outside the philosophy of mind. Structural Realism (Waltz, Mearsheimer) claims the anarchic international system selects for similar state behavior regardless of leadership — individual agency is largely substitutable. Liberal Institutionalism (Keohane, Nye) and Democratic Peace theory claim agency at multiple scales (leaders, regimes, institutions, transnational actors) materially shapes international behavior. Constructivism (Wendt, Finnemore) — the third position your framing implies — explicitly addresses the agent-structure problem and is the IR school most natively friendly to complexity-theoretic frameworks. The atlas's frameworks don't decide this debate, but each one frames it differently and several make empirical predictions that could be tested against IR data.",
    setup: "States interact in a system with no overarching authority (anarchy). Outcomes include war, peace, alliance, trade, sanctions, diplomacy, treaty formation. The empirical record (Correlates of War dataset, Militarized Interstate Disputes, ICEWS, GDELT) covers ~200 years of state behavior. The theoretical question: are observed patterns explained primarily by (a) system structure forcing similar behavior, (b) agency of leaders / regimes / institutions producing variation that compounds, (c) ideas, norms, and constitutive identities (shared meanings about what 'sovereignty' or 'security' mean)? Important nuance not in the user's framing: realism doesn't deny human agency exists — it denies that agency makes structural difference to outcomes. Liberalism doesn't just say 'agency is positive' — it says agency is real and consequential at multiple scales. Constructivism says structure and agency mutually constitute each other.",
    mappings: [
      { concept: "Structural Realism (philosophy)", how: "Ontic SR (Ladyman-Ross) says relational structure is primary — what exists are positions in a system, not entities with intrinsic natures. This is structurally analogous to Waltz's structural realism in IR: states are 'like units' (functionally similar) and the system's anarchic structure determines outcomes. The two structural realisms developed independently (philosophy of physics; IR theory) but make parallel ontological moves. Both are vulnerable to the same objection: if structure determines everything, why do similar systems produce different outcomes? Liberalism and constructivism press exactly this objection in IR." },
      { concept: "Causal Emergence (Hoel)", how: "The agency-structure debate is empirically: at which scale does intervention carry the most causal information about outcomes? Hoel's EI applied to international politics data could in principle decide between (a) individual leader scale (favored by classical realism, foreign policy analysis), (b) state/regime scale (favored by liberalism), (c) system-level dyadic or systemic scale (favored by structural realism). No one has run this analysis cleanly on IR data, but the framework provides the empirical machinery. If EI maximizes at the system level → favorable to structural realism. If at the regime level → favorable to liberalism. Open research direction." },
      { concept: "Markov Blanket / Active Inference", how: "States can be modeled as Markov-blanketed agents with generative models of the international environment, minimizing free energy through diplomatic/military action. This is broadly compatible with realism (states as unitary rational actors with security models) BUT the Markov blanket assumption is contested for diffuse social entities (Bruineberg et al. 2022 critique). The blanket framework works better for tightly bounded states (Singapore, Israel) than for blurry ones (the EU as a state? China's foreign business arms?). Implication: AIF favors a realist-flavored ontology of unitary state actors, but its applicability degrades for the actors that liberalism and constructivism most care about." },
      { concept: "ε-machine / Statistical Complexity", how: "Park et al. 2007 reconstructed ε-machines from S&P 500 tick data and found statistical complexity declined over 20 years — markets became 'more efficient' in IT terms. The same method applied to militarized interstate dispute time series, or to diplomatic event data (GDELT, ICEWS), could reveal whether international system dynamics have rich internal causal structure (favoring constructivism: there's lots of contingent meaning-making) or low statistical complexity (favoring structural realism: the system reduces to a few state variables). Not yet attempted. One of the cleanest empirical tests available." },
      { concept: "Network Science", how: "International relations IS literally a network problem: trade networks, alliance networks, diplomatic recognition networks, treaty co-membership networks. Decades of work (Maoz, Hafner-Burton, Montgomery) shows network structure predicts conflict, trade, and policy diffusion better than dyadic or systemic theories alone. This is a major empirical strike AGAINST pure structural realism (which treats the system as flat) and FOR a relational view that includes liberal institutionalism (institutions = nodes + ties) and constructivism (norms diffuse via network topology)." },
      { concept: "Constructivism (Wendt) ↔ Critical Realism (Bhaskar)", how: "Wendt explicitly drew on Bhaskar's critical realism in 'The Agent-Structure Problem in International Relations Theory' (1987). The CR move: agents and structures mutually constitute each other across stratified ontology levels (individual → state → international society). This is the IR position most natively friendly to the atlas's productive frameworks — CR allows emergent macro-level causal powers without denying micro-level agency. If you want one philosophical bridge between IR theory and the complexity atlas, it's Bhaskar's CR via Wendt." },
      { concept: "Process Philosophy", how: "Process metaphysics (Whitehead, Dupré, Nicholson) fits constructivism better than realism: states aren't substances with intrinsic natures but stabilized process patterns. 'France' is a stabilized pattern of practices, institutions, identifications — not an entity with an essence. Realism implicitly assumes substance metaphysics (states have intrinsic natures: 'great power,' 'rogue state'); constructivism implicitly assumes process metaphysics (state identities are continuously reproduced through practice). This metaphysical commitment is rarely articulated in IR but matters for which scientific moves you can defend." },
      { concept: "Substance Metaphysics", how: "Realism in IR aligns with substance metaphysics: states are bearers of essential properties (sovereignty, capability, intent) that have causal powers regardless of relations. This view dovetails with primordialist nationalism, geopolitics-as-destiny, and 'great power competition' framings. The metaphysical critique of substance metaphysics in the atlas (SR, PRO oppose; PCM tension) is also implicitly a critique of realism in IR — you can't reject substance metaphysics in physics and then assume it in foreign policy without inconsistency." },
      { concept: "Powers / Dispositionalism", how: "Realism's central concept of 'national power' is dispositional: a state's military power is what it WOULD do under circumstances (deterrent capability, war potential). Powers metaphysics gives a clean ontology here: states have dispositional powers (industrial capacity → war-making capability; alliance commitments → triggered defense behavior) that manifest under specific conditions. This is a metaphysical home for realism that survives the substance-metaphysics critique: states have powers, but those powers can be relational rather than intrinsic." },
      { concept: "New Mechanism", how: "Foreign Policy Analysis (FPA) — the liberal subfield focused on how decisions actually get made — uses MEC-style explanation: identify the entities (decision-makers, agencies, advisors), the activities (bureaucratic bargaining, group dynamics, cognitive biases), and the organization (decision procedures) producing observed foreign policy. Allison's 'Essence of Decision' (1971) is the canonical example. Mechanism-style explanation is methodologically liberal-friendly: it requires getting inside the black box, contra structural realism's deliberate use of states as unit-of-analysis." },
      { concept: "Evolutionary Dynamics", how: "International system as selection environment for state strategies. Selection acts on states that fail to maintain themselves (defeated, collapsed, absorbed). The history of state forms (city-state → empire → nation-state → ?) shows selection at the species-of-state level. This view is compatible with both structural realism (the system selects for security-maximizing strategies; non-conformists die) and constructivism (selection acts on norms and identities, not just capabilities)." },
      { concept: "Cybernetics", how: "Deterrence is a cybernetic concept par excellence: a feedback control system maintaining a setpoint (peace, status quo) through credible threat of punishment. Cold War IR theory was explicitly informed by cybernetics (Wiener consulted on early game theory; Schelling's work on signaling is broadly cybernetic). The Conant-Ashby theorem applies: a good deterrent must model the adversary — which is why intelligence failures cause deterrence failures, and why mutual transparency stabilizes deterrence. This is solid common ground between IR theory and the atlas." },
      { concept: "Levels / Hierarchy", how: "Waltz's 'three images' of international politics — individual, state, system — is a stratified ontology (Bhaskar would recognize it). Realism privileges the system level; liberalism privileges the state level (and within-state institutions); constructivism allows traffic across all three. The atlas's commitment to multi-level reality (Rainforest Realism) is closest to constructivism — but doesn't endorse any specific level as universally privileged." },
      { concept: "Causation / Counterfactual", how: "The classic IR counterfactual: 'Would WWI have happened without the assassination of Franz Ferdinand?' Realism: yes, structural pressures meant war was likely regardless. Liberalism: no, the specific decisions of leaders during the July Crisis mattered. The disagreement is empirical: how much do micro-level decisions matter when macro-structural pressure is strong? Pearl's framework + good event-data could in principle answer this for many historical cases, though counterfactual identification is hard with non-experimental data." },
    ],
    lesson: "The IR debate is the agency-structure debate from another vocabulary, played out with stakes (war, peace, billions of lives). Three honest observations: (1) Your framing of realism vs liberalism captures the structural-realism vs liberal-institutionalism axis correctly but missed constructivism, which is the school most natively compatible with the atlas — Wendt explicitly built constructivism on Bhaskar's critical realism. (2) The empirical machinery to actually decide between these positions (causal emergence on IR event data, ε-machine analysis of system dynamics, network analysis of institutional ties) exists and is mostly unused — the same gap as in the agents-as-research-instruments framing. (3) Metaphysical commitments matter: realism is implicitly substance-metaphysical (states with essential natures), constructivism is implicitly process-metaphysical (states as stabilized practice patterns), and you can't claim philosophical sophistication while being inconsistent about this across domains. Practical corollary: if you find yourself confidently asserting that 'states are rational unitary actors' OR that 'agency is what matters in foreign policy,' you've taken a metaphysical position you probably should defend rather than assume. The atlas equips you to defend either position — but not to pretend the choice doesn't exist.",
  },
];

// ─── METHODOLOGY / THINKING IN SYSTEMS ───────────────────────────────────────
const METHODS = [
  {
    id: "diagnostic-checklist",
    title: "Diagnostic Checklist (the daily tool)",
    intro: "When something behaves strangely — a project that won't finish, a habit that won't change, a team that keeps stalling — work through these layers from concrete to abstract. Most strange behavior dissolves before you reach the philosophical layer.",
    sections: [
      {
        heading: "Layer 1 — Classical systems vocabulary (Meadows lineage)",
        bullets: [
          "Where are the **stocks**? What is accumulating?",
          "Where are the **flows**? What controls their rates?",
          "Where are the **feedback loops**? Reinforcing or balancing?",
          "Where are the **delays**? Does response lag cause oscillation or overshoot?",
          "What is the **attractor**? Where does the system want to settle?",
          "What is the **basin**? When does it shift to a different attractor?",
          "Is there sufficient **requisite variety** in the regulator? Ashby: H(R) ≥ H(D).",
        ],
      },
      {
        heading: "Layer 2 — Information & coupling (Shannon, Schreiber)",
        bullets: [
          "What is the **mutual information** between key variables? When linear correlation is zero, MI catches nonlinear coupling.",
          "What does **transfer entropy** tell you about directionality of information flow?",
          "What information is being **dissipated** (irreversible losses) vs preserved across time?",
          "Where are the **boundaries**? Compute or identify a Markov blanket if one exists.",
        ],
        formulas: [
          { f: "I(X;Y) = Σ p(x,y) log[p(x,y) / (p(x)p(y))]", label: "Mutual information" },
          { f: "T(X→Y) = I(Y_{t+1}; X_t | Y_t)", label: "Transfer entropy" },
          { f: "MB(X) = pa(X) ∪ ch(X) ∪ pa(ch(X))", label: "Markov blanket (graphical)" },
        ],
      },
      {
        heading: "Layer 3 — Causation & scale (Pearl, Hoel, Crutchfield)",
        bullets: [
          "What's the **causal graph**? Where are the edges? Which are testable by intervention?",
          "Could a **confounder** explain what looks like X→Y? Apply the backdoor criterion.",
          "At what **scale** is causation most efficient? Try the EI test across candidate coarse-grainings.",
          "Are the system's **causal states** discoverable? Build a small ε-machine for a coarse observable.",
        ],
        formulas: [
          { f: "P(Y | do(X=x)) = Σ_z P(Y|X,Z=z) P(Z=z)", label: "Backdoor adjustment" },
          { f: "EI(S) = I(I_D ; E_D),  uniform intervention prior I_D", label: "Effective information" },
          { f: "Causal emergence ⇔ ∃ π: EI(π(X)) > EI(X)", label: "Hoel's CE test" },
        ],
      },
      {
        heading: "Layer 4 — Selection, relational structure, dissipation (EVO, NET, TH)",
        bullets: [
          "Is this system **evolving**? Variation + heritability + differential fitness = guaranteed evolution (Lewontin).",
          "Is the dominant structure **relational**? Map nodes and edges; check degree distribution and modularity.",
          "Is the system **driven and dissipative**? Then expect non-equilibrium steady-states, not equilibrium ones.",
          "Could **dissipative adaptation** (England) be reorganizing structure to better dissipate the drive?",
        ],
        formulas: [
          { f: "ẋᵢ = xᵢ (fᵢ − ⟨f⟩)", label: "Replicator equation" },
          { f: "P(σ) / P(−σ) = e^σ", label: "Crooks fluctuation theorem" },
          { f: "Q = (1/2m) Σ_ij [Aᵢⱼ − kᵢkⱼ/2m] δ(cᵢ, cⱼ)", label: "Network modularity" },
        ],
      },
      {
        heading: "Layer 5 — Decision points (the philosophical layer)",
        bullets: [
          "Am I treating macro structure as **real or as convenient redescription**? Different metaphysical frameworks (SR, CR, MEC, POW) give different answers — be explicit.",
          "Is the partition I'm using **observer-chosen or dynamics-selected**? CM and RG select; EI and real-pattern partly choose.",
          "If observer-chosen: am I missing the natural partition the dynamics select?",
          "Am I conflating Friston's **variational free energy** with **thermodynamic free energy**? They share a name and structure but are distinct objects.",
        ],
      },
    ],
    closing: "Run this on a misbehaving codebase, a slow team, a stuck project, your own habits, an economy, an ecosystem, a research program. Most \"mysterious\" behavior is just unmapped behavior.",
  },

  {
    id: "multi-scale-workflow",
    title: "Multi-Scale Analysis Workflow",
    intro: "Almost every interesting system spans multiple scales. The point of multi-scale analysis is finding the level where your specific question is most cleanly answerable — not picking one level a priori and forcing everything into it.",
    sections: [
      {
        heading: "Phase 1 — Identify candidate levels",
        bullets: [
          "What are the natural **variables** at different scales?",
          "Are there obvious **timescale separations** (fast/slow dynamics)?",
          "Are there obvious **spatial separations** (local/global)?",
          "Are there obvious **functional separations** (component/system)?",
          "Network structure — are there densely-connected **communities**, with the inter-community structure forming the higher level?",
        ],
      },
      {
        heading: "Phase 2 — Test each level for real-pattern status",
        intro: "For each candidate level k, run the tests that fit your goal. Multiple criteria converging → high confidence the level is real. One criterion alone → useful but contestable.",
        bullets: [
          "**Compression** — does it compress data better than alternative scales? (MDL / K-criterion.)",
          "**Effective information** — does it have higher EI than other scales? (Hoel's CE test.)",
          "**Causal states** — does it have causal states that screen off past from future? (Crutchfield's CM test.)",
          "**Markov blanket** — does it have a stable blanket? (FEP test for agency. Use with Aguilera-style caveats.)",
          "**Network modularity** — does it correspond to a high-Q community partition? (NET test.)",
          "**Selection** — does this level correspond to a unit of selection? (EVO test, especially for biology / culture / technology.)",
        ],
        formulas: [
          { f: "Real pattern (Dennett): π is real ⇔ K(data | π) + K(π) < K(data)", label: "Compressibility test" },
          { f: "Crutchfield: σ(h) = { h' : P(future|h') = P(future|h) }", label: "Causal-state equivalence" },
          { f: "Hoel:  CE ⇔ EI(π(X)) > EI(X)", label: "Causal emergence" },
        ],
      },
      {
        heading: "Phase 3 — Map inter-level relations",
        bullets: [
          "What **coarse-graining** π takes you from level k to level k+1?",
          "Is the coarse-graining **dynamics-selected** (CM, RG, attractor basins) or **observer-chosen** (EI, real-pattern)?",
          "What information is **lost** in the transition? Within-class entropy H(micro | macro).",
          "What **new relations** emerge at the higher level that don't exist at the lower? (This is the quotient effect — coarse-graining is not just compression.)",
        ],
        formulas: [
          { f: "π : X → Y,  many-to-one,  p(y) = Σ_{x ∈ π⁻¹(y)} p(x)", label: "Coarse-graining map" },
          { f: "H(X) = H(Y) + H(X | Y)", label: "Information lost = H(X|Y)" },
        ],
      },
      {
        heading: "Phase 4 — Identify the analytical level (task-relative)",
        intro: "Most questions live at one privileged level. Match the level to the question:",
        bullets: [
          "**Predictive** questions → level with highest **excess entropy** E = I(past; future).",
          "**Causal** questions → level with highest **effective information** EI.",
          "**Mechanistic** questions → lowest level where the mechanism is intact (MEC).",
          "**Agency** questions → level with stable **Markov blanket**.",
          "**Evolutionary** questions → the unit of selection (gene/individual/group/lineage).",
          "**Selection-history** questions → assembly index × copy number (AT).",
        ],
      },
    ],
    closing: "The frameworks tell you which level to work at. Don't impose one a priori; pick the level that the criterion-of-interest is highest on.",
  },

  {
    id: "micro-macro-synthesis",
    title: "Micro ↔ Macro — The Synthesis Page",
    intro: "Comprehensive understanding of complexity means holding micro and macro simultaneously: knowing what each level CAN and CANNOT say, and which transitions between them are well-defined. This is the synthesis the whole framework points toward.",
    sections: [
      {
        heading: "What each level is GOOD at",
        bullets: [
          "**Micro is good at**: mechanism, identifying what physically does what, force-by-force causation, intervention at the substrate, falsification by direct measurement.",
          "**Macro is good at**: prediction with manageable variables, identifying invariants, agency / functional language, causation efficient at the right scale (Hoel's CE), real patterns (Dennett), policy and intervention at human scales.",
          "Different levels answer different questions. Neither is privileged in general — both are real, both are necessary, and the choice is task-relative.",
        ],
      },
      {
        heading: "What each level is BAD at",
        bullets: [
          "**Micro is bad at**: prediction (combinatorial explosion), explanation of high-level invariants (you can't see RG universality from micro details), agency-talk (mechanism without function loses what the system is FOR).",
          "**Macro is bad at**: mechanism, intervention granularity, accounting for substrate constraints, distinguishing 'the real macro pattern' from 'a convenient redescription' without careful testing.",
        ],
      },
      {
        heading: "Well-defined transitions between levels",
        intro: "These are the bridges you can actually trust:",
        bullets: [
          "**Renormalization group (RG)**: explicit coarse-graining at criticality. Universality classes are real.",
          "**ε-machines (CM)**: minimal-sufficient causal states are discovered, not chosen — uniquely defined up to isomorphism.",
          "**Attractor-basin partitions**: dynamics-selected; the partition is real because it's what survives long-time evolution.",
          "**Hoel's CE**: macro EI > micro EI is empirically computable from transition matrices.",
          "**Network modularity**: Q-maximizing partition is a defined optimization (with caveats — multiple high-Q solutions can coexist).",
        ],
        formulas: [
          { f: "RG:  K_{n+1} = R[K_n] → K*",        label: "RG flow to fixed point" },
          { f: "Cμ = H(σ),  σ = causal states",      label: "Statistical complexity" },
          { f: "EI(macro) > EI(micro)",              label: "CE marker" },
        ],
      },
      {
        heading: "Forbidden moves",
        bullets: [
          "**Inferring causation from mutual information alone** — MI is symmetric and confounder-blind.",
          "**Treating supervenience as reduction** — supervenience allows multiple realizers; reduction requires bridge laws.",
          "**Confusing observer-relative with observer-independent partitions** — only some coarse-grainings (CM, RG) are observer-independent.",
          "**Mistaking variational free energy for thermodynamic free energy** — same name, distinct objects.",
          "**Reading 'macro is just micro' OR 'macro is irreducibly novel' as obvious** — the choice between weak emergence and strong emergence is a real, defensible decision, not a default.",
        ],
      },
      {
        heading: "The high-bandwidth view",
        intro: "When you've internalized the framework, you can hold all of this at once:",
        bullets: [
          "A system has a substrate (micro) and a description (macro) related by a coarse-graining π.",
          "π loses information H(X|Y), preserves I(X_past; X_future) up to E (excess entropy), and is the right π if EI is maximized or Cμ is minimized for the task.",
          "Causation at the macro level is real if EI(macro) > EI(micro), or in the weaker sense if mechanisms at the macro level produce the phenomenon.",
          "Agency is the persistence of a Markov-blanketed sub-pattern under perturbation — when such a blanket exists, which is not always.",
          "Selection (EVO), dissipation (TH), and network topology (NET) act simultaneously across scales — they aren't competing accounts but complementary lenses.",
          "Underneath all of this sit metaphysical commitments — substance vs process, powers vs regularities, single-level vs stratified — that you cannot avoid making, only avoid being explicit about.",
        ],
      },
    ],
    closing: "If you can hold micro and macro simultaneously, switch between them as the question demands, and remain explicit about which transitions are rigorous vs which are methodological choices — you are using the framework. Everything else is vocabulary.",
  },

  {
    id: "emergence-detection",
    title: "Detecting Emergence (operational)",
    intro: "\"Is this system emergent?\" is usually the wrong question. The right question depends on which kind of emergence you mean.",
    sections: [
      {
        heading: "Weak emergence (Bedau)",
        bullets: [
          "Test: can you predict macro behavior from micro dynamics in closed form, or must you simulate?",
          "If you must simulate → **weak emergence** (computational irreducibility).",
          "If a closed-form macro law exists → likely no significant emergence (just complicated dynamics).",
          "Almost all interesting systems pass this test trivially. Cellular automata, turbulence, financial markets, neural networks — all weakly emergent.",
        ],
        formulas: [
          { f: "K(x_t | x_0, f) ≈ t · c", label: "No-shortcut: trajectory is incompressible" },
        ],
      },
      {
        heading: "Causal emergence (Hoel)",
        bullets: [
          "Test: compute effective information at multiple scales.",
          "If ∃ a coarse-graining π such that EI(π(X)) > EI(X) → **causal emergence** is present and measurable.",
          "If no such π exists → no CE.",
          "Computable directly from the transition matrix; no metaphysics required. Caveat: depends on intervention prior (Eberhardt critique).",
        ],
        formulas: [
          { f: "CE ⇔ ∃ π: EI(π(X)) > EI(X)", label: "Hoel's operational marker" },
        ],
      },
      {
        heading: "Strong emergence",
        bullets: [
          "Test: are there macro causal interactions that don't supervene on micro? (Macro change without micro change.)",
          "Almost certainly **no**, given physical closure.",
          "Exception: only if you genuinely believe quantum measurement, biological organisms, or consciousness instantiate ontological discontinuity.",
          "Critical Realism (Bhaskar) provides the cleanest metaphysical framework for strong emergence — if you want to defend it, that's where to start.",
        ],
        formulas: [
          { f: "Strong marker (contested):  H(E | do(M=m), X_micro) > 0", label: "Macro carries irreducible info" },
        ],
      },
      {
        heading: "Workflow",
        bullets: [
          "1. Start with **weak emergence** as the baseline.",
          "2. Compute EI across scales to test for **causal emergence**.",
          "3. Only invoke **strong emergence** if (1) and (2) demonstrably fail to capture the phenomenon — rare in practice.",
        ],
      },
    ],
    closing: "Distinguishing types of emergence gives you precise empirical questions instead of philosophical disputes. \"Emergence\" is not one thing — and the differences are operational.",
  },

  {
    id: "iceberg-where-systems-thinkers-look",
    title: "The Iceberg — Where to Look",
    intro: "Most analysis looks at the wrong level. The visible surface is rarely where leverage lives.",
    sections: [
      {
        heading: "Level 1 — Events (visible, low leverage)",
        bullets: [
          "What happened? Who did what? The news layer.",
          "Most attention goes here. Least leverage to change anything.",
          "Describes the current trajectory but doesn't reach what's producing it.",
        ],
      },
      {
        heading: "Level 2 — Patterns (observable with effort, medium leverage)",
        bullets: [
          "What keeps happening? What's the recurring shape?",
          "Requires looking across multiple events.",
          "Identifies trends, cycles, repeated failures.",
          "Some leverage: you can interrupt patterns.",
        ],
      },
      {
        heading: "Level 3 — Structure (requires modeling, high leverage)",
        bullets: [
          "What feedback loops, stocks, delays, and rules produce these patterns?",
          "Most concrete leverage lives here.",
          "Requires explicit causal model — diagnostic checklist operates here.",
        ],
      },
      {
        heading: "Level 4 — Scales / Emergence (requires multi-scale analysis, very high leverage)",
        bullets: [
          "At what scale is causation maximally efficient? Are there real patterns being missed at the current scale?",
          "Often what's broken at one level is fine at another.",
          "Often the lever you want is at a different scale than the symptom.",
          "Multi-scale workflow operates here.",
        ],
      },
      {
        heading: "Level 5 — Paradigms (rarely accessible, highest leverage)",
        bullets: [
          "What worldview makes this structure feel normal?",
          "What would have to change in your conceptual frame to see this differently?",
          "Hardest to change — but changes everything when it does.",
          "Structural realism, process metaphysics, or substance metaphysics — the choice of paradigm shapes everything downstream.",
        ],
      },
    ],
    closing: "Operating rule: when stuck at one level, go up one level. Most \"intractable\" problems are intractable because they're being addressed at the wrong level.",
  },

  {
    id: "coarse-graining-recipe",
    title: "Coarse-Graining Recipe",
    intro: "When you need to move from micro to macro analysis, the question is HOW to coarse-grain. Bad coarse-graining hides structure; good coarse-graining reveals it.",
    sections: [
      {
        heading: "Good coarse-graining — targets the system's own structure",
        bullets: [
          "Identify the system's natural **timescale separation**. Slow variables are macro; fast variables get integrated out.",
          "Identify **attractor basins**. Partition microstates by which basin they flow into.",
          "Test: does the macro partition **preserve prediction**? (CM test.)",
          "Test: does the macro partition **increase effective information**? (CE test.)",
          "Test: does the macro partition correspond to **community structure** in the relational network? (NET test.)",
        ],
      },
      {
        heading: "Bad coarse-graining — arbitrary partitions",
        bullets: [
          "Equal-volume binning of state space (ignores dynamics).",
          "Threshold-based partitioning by static observable (ignores trajectory).",
          "Functional partitioning by intuitive category (might be right but unjustified).",
        ],
      },
      {
        heading: "Operational steps",
        bullets: [
          "1. Begin with the finest grain available. Compute H(X), Cμ(X), or EI(X) as appropriate.",
          "2. Try candidate coarse-grainings π₁, π₂, … Compute the same measures on πᵢ(X).",
          "3. Compare against baseline (see formula box).",
          "4. Iterate until you find the scale that maximizes the criterion you care about.",
        ],
        formulas: [
          { f: "H(π(X)) ≪ H(X)  AND  prediction lost  ⇒  bad",  label: "Compression destroys signal" },
          { f: "H(π(X)) ≪ H(X)  AND  prediction preserved  ⇒  real compression", label: "Useful compression" },
          { f: "EI(π(X)) > EI(X)  ⇒  causal emergence at this scale", label: "Hoel's marker" },
        ],
      },
      {
        heading: "Critical warnings",
        bullets: [
          "Different criteria can recommend **different coarse-grainings**. Be explicit about what you're optimizing for.",
          "Coarse-graining is **not just compression** — it's a quotient. New relations emerge on the equivalence classes.",
          "The \"best\" coarse-graining is **task-relative**. There's no scale-independent answer.",
        ],
      },
      {
        heading: "Worked example",
        bullets: [
          "**Chaotic dynamical system**: \"average over short time\" is a bad coarse-graining — it loses information about which attractor.",
          "\"Partition by attractor basin\" is a good coarse-graining — preserves long-time prediction.",
          "Same system, two coarse-grainings, very different results. The choice matters.",
        ],
      },
    ],
    closing: "Coarse-graining well is the single most useful analytical move in complexity science. Coarse-graining poorly is the single most common methodological failure.",
  },

  {
    id: "common-pitfalls",
    title: "Common Pitfalls — Read These Before You Start",
    intro: "These are the failure modes that cost time and produce wrong answers. Each is common enough to be worth pre-flagging.",
    sections: [
      {
        heading: "1. Treating frameworks as competitors",
        bullets: [
          "**Wrong**: \"Is this Hoel-style causal emergence or Crutchfield-style computational mechanics?\"",
          "**Right**: \"What does each framework reveal? Where do they converge, where do they diverge?\"",
          "Different frameworks answer different questions. The Graph tab makes the relationships explicit — use it.",
        ],
      },
      {
        heading: "2. Confusing weak and strong emergence",
        bullets: [
          "**Wrong**: \"This system is emergent\" (which kind?)",
          "**Right**: \"This system is weakly emergent (computationally irreducible) but not strongly emergent (no downward causation).\"",
          "The types are categorically different. Always distinguish them.",
        ],
      },
      {
        heading: "3. Assuming the observer-relative / objective question is settled",
        bullets: [
          "**Wrong**: \"Real patterns are observer-independent\" (or the opposite).",
          "**Right**: \"CM and RG give observer-independent partitions; real-pattern and EI involve methodological choices. Be explicit.\"",
          "This is a real decision point, not a matter of taste.",
        ],
      },
      {
        heading: "4. Chasing metaphysics when math suffices",
        bullets: [
          "**Wrong**: \"But is causation REAL or just regularity?\"",
          "**Right**: \"I have measurable transfer entropy / effective information / interventional distribution. The metaphysical question doesn't change the measurement.\"",
          "Productive frameworks bracket Humean/realist debates. Stay there unless the question requires going deeper.",
        ],
      },
      {
        heading: "5. Confusing levels with timescales",
        bullets: [
          "**Wrong**: assuming macro = slow.",
          "**Right**: macro can be slow (thermodynamic limit) or fast (inference happening over a network state).",
          "Levels are partition structures; timescales are separate (though often correlated).",
        ],
      },
      {
        heading: "6. Applying one framework everywhere",
        bullets: [
          "**Wrong**: trying to use Pearl's do-calculus on every problem.",
          "**Right**: match framework to question. Predictive → CM. Scale → CE. Agency → AIF (with caveats). Selection → EVO. Topology → NET.",
        ],
      },
      {
        heading: "7. Neglecting timescale separation",
        bullets: [
          "Almost every successful coarse-graining exploits timescale separation.",
          "If your system doesn't have one, coarse-graining is much harder and may not yield clean macro structure.",
        ],
      },
      {
        heading: "8. Treating Markov blankets as metaphysically heavy",
        bullets: [
          "**Wrong**: \"If it doesn't have a Markov blanket, it's not a real system.\"",
          "**Right**: Markov blankets are useful when they exist. Many systems don't have clean blankets (Aguilera et al. 2022). That's fine.",
        ],
      },
      {
        heading: "9. Conflating Friston FEP with thermodynamic free energy",
        bullets: [
          "**Wrong**: \"The brain literally minimizes thermodynamic free energy.\"",
          "**Right**: variational FEP is a KL divergence over a generative model. Thermodynamic FE is U − TS. Same name, different objects.",
        ],
        formulas: [
          { f: "F_var[q] = D_KL(q ‖ p_posterior) − log p(o)", label: "Friston (information)" },
          { f: "F_thermo = U − TS",                           label: "Helmholtz (physical)" },
        ],
      },
      {
        heading: "10. Ignoring the metaphysical commitments",
        bullets: [
          "Every productive framework has implicit metaphysical commitments — substance/process, powers/regularities, single-level/stratified.",
          "The metaphysical frameworks (POW, PRO, MEC, CR, SUB) make these explicit.",
          "You don't have to commit to one — but pretending you have no commitment is itself a commitment.",
        ],
      },
    ],
    closing: "Pre-flag these to skip the time-and-credibility cost of discovering them mid-argument.",
  },

  {
    id: "common-confusions",
    title: "Common Confusions — The Conflations the Field Lives On",
    intro: "Conceptual conflations that produce most bad arguments in the literature. If you can't articulate the distinction sharply, you're using the vocabulary as decoration. Memorize the distinctions before you need them.",
    sections: [
      {
        heading: "1. Entropy vs. surprisal",
        bullets: [
          "Surprisal i(x) = −log p(x) is a property of an INDIVIDUAL outcome.",
          "Entropy H(X) = E[i(x)] is the EXPECTED surprisal across the distribution.",
          "Saying \"this event has high entropy\" is a category error. Events have surprisal; distributions have entropy.",
        ],
        formulas: [
          { f: "i(x) = −log p(x)",       label: "Surprisal (per outcome)" },
          { f: "H(X) = E[i(x)]",          label: "Entropy (per distribution)" },
        ],
      },
      {
        heading: "2. Mutual information vs. causation",
        bullets: [
          "I(X;Y) > 0 says X and Y are statistically related. It says NOTHING about who causes whom.",
          "To get causation you need one of: (a) intervention (do-calculus), (b) temporal ordering + exclusion of common causes (TE, Granger — partial), or (c) structural commitments (SCM).",
          "MI is necessary but never sufficient for causal claims.",
        ],
        formulas: [
          { f: "I(X;Y) > 0  ⇏  X causes Y", label: "Symmetric and confounder-blind" },
          { f: "P(Y | do(X)) ≠ P(Y | X)  ⇒  causal", label: "Intervention test" },
        ],
      },
      {
        heading: "3. Weak vs. strong emergence",
        bullets: [
          "**Weak** (Bedau): macro is derivable from micro but only via simulation. Compatible with physicalism.",
          "**Strong** (Humphreys, O'Connor): macro carries causal information not present in micro at all. Contested.",
          "Mixing them collapses the productive distinction.",
        ],
      },
      {
        heading: "4. Supervenience vs. reduction",
        bullets: [
          "**Supervenience**: no macro change without micro change.",
          "**Reduction**: macro is derivable / definable in terms of micro.",
          "Supervenience does NOT entail reduction (Fodor's multiple-realizability argument). Many systems supervene without reducing.",
        ],
      },
      {
        heading: "5. Computation vs. causation",
        bullets: [
          "A system can compute a function f without being causally structured by f.",
          "Many \"computational\" descriptions of physical systems (brain as Bayesian inference, immune system as decision theory) are functional, not causal.",
          "Crutchfield's CM is the rare framework that bridges these via causal states; most don't.",
        ],
      },
      {
        heading: "6. Observer-relative vs. observer-independent partitions",
        bullets: [
          "**Observer-independent**: RG fixed points, ε-machine causal states — the dynamics select them.",
          "**Methodologically chosen**: real-pattern criterion, EI-maximization — involve methodological commitments (which compression criterion, which intervention prior).",
          "Conflating these is how \"objective emergence\" gets oversold.",
        ],
      },
      {
        heading: "7. Correlation length diverging vs. system \"being critical\"",
        bullets: [
          "Power-law correlations do NOT entail criticality in the rigorous RG sense.",
          "Many systems generate power laws by other mechanisms (preferential attachment, Yule processes, log-normal mixtures).",
          "\"Critical\" is a strong claim with specific tests (universality class, exponent relations). \"Power-law\" is just a fitted distribution.",
        ],
      },
      {
        heading: "8. Probability vs. propensity vs. frequency",
        bullets: [
          "The same Σ p(x) appears in all three interpretations with different ontological commitments.",
          "**Frequentist**: long-run frequency in a reference class.",
          "**Bayesian**: degree of belief.",
          "**Propensity**: dispositional fact about the system (POW-friendly).",
          "Math is identical; metaphysics differs. Know which interpretation you're committing to.",
        ],
      },
      {
        heading: "9. Structural equations vs. statistical models",
        bullets: [
          "A regression y = βx + ε is a statistical association.",
          "A structural equation Y := f(parents) + noise is a CAUSAL claim about what would happen under interventions.",
          "Reading regressions as structural is the most common applied error in causal inference.",
        ],
        formulas: [
          { f: "y = βx + ε",          label: "Statistical (associational)" },
          { f: "Y := f(pa(Y), ε_Y)",   label: "Structural (causal, do-ready)" },
        ],
      },
      {
        heading: "10. Stationary vs. ergodic",
        bullets: [
          "**Stationary**: marginal distributions don't change with time.",
          "**Ergodic**: time averages equal ensemble averages.",
          "Stationarity is weaker. Many systems are stationary but not ergodic (broken symmetry, multiple basins).",
          "Confusing these breaks every estimation procedure that assumes ergodicity to estimate ensemble quantities from a single trajectory.",
        ],
      },
      {
        heading: "11. Markov vs. non-Markovian",
        bullets: [
          "**Markov**: future ⊥⊥ past | present.",
          "Most real systems are non-Markovian at the observable level (memory).",
          "Computational mechanics' trick: find an enriched state (causal states) for which Markov HOLDS. Markovianity is achieved by state choice.",
        ],
        formulas: [
          { f: "Markov:  P(X_{t+1} | X_t, X_{<t}) = P(X_{t+1} | X_t)", label: "Memorylessness given current state" },
        ],
      },
      {
        heading: "12. Free energy (Friston) vs. free energy (physics)",
        bullets: [
          "**Friston (variational)**: F = D_KL(q ‖ p_posterior) − log p(o). An information quantity.",
          "**Thermodynamic (Helmholtz)**: F = U − TS. A physical quantity.",
          "They share a name and a formal structure but they are distinct objects. Pop accounts conflate them.",
        ],
      },
    ],
    closing: "Each confusion costs hours when you encounter it in others' arguments, and credibility when it appears in your own.",
  },

  {
    id: "mind-cognition-workflow",
    title: "Mind & Cognition — Cross-Framework Workflow",
    intro: "Among the deepest questions complexity science approaches, but the field is genuinely fractured. Four major frameworks each claim to capture what cognition is: AIF (cognition as inference), 4E (cognition as embodied coupling), PHE (cognition as lived experience), and CYB (cognition as feedback control). Each has formal machinery and serious commitments. This page is a workflow for navigating the question without forcing premature unification.",
    sections: [
      {
        heading: "The four lenses on mind",
        intro: "Before choosing a framework, see what each one MUST address and what each one CAN avoid.",
        bullets: [
          "**AIF (Active Inference / FEP)** — cognition is variational inference under a generative model. Mind = predictive machinery minimizing surprise. Mathematically rigorous; representationally committed. Contested whether it captures phenomenal experience.",
          "**4E (Embodied, Embedded, Extended, Enacted)** — cognition is sensorimotor coupling between body and world. Mind extends past the skull; basic cognition has no representations. Direct heir to second-order cybernetics + phenomenology.",
          "**PHE (Phenomenology)** — cognition's primary data is first-person lived experience, accessible only via disciplined introspection. Husserl's intentionality, Merleau-Ponty's lived body. Methodologically distinct from third-person science.",
          "**CYB (Cybernetics)** — cognition is feedback regulation. The Conant-Ashby theorem (every good regulator is a model of the system) is the foundational result. Pre-dates and partly grounds the others.",
        ],
      },
      {
        heading: "Phase 1 — Identify what kind of mind-question you're asking",
        bullets: [
          "Is the question about **mechanism** (how does cognition WORK)? → AIF, MEC, CYB all contribute.",
          "Is the question about **phenomenal character** (what IS it like to have this experience)? → PHE is the native framework; 4E gives embodiment-grounded accounts.",
          "Is the question about **boundaries of cognition** (where does mind start/stop)? → 4E's extended mind thesis; AIF's Markov blanket; CYB's feedback-loop closure.",
          "Is the question about **intentionality / aboutness** (what makes a state ABOUT something)? → PHE native; AIF claims naturalization; MEC offers function-based reduction.",
          "Is the question about **agency** (what makes a system an agent)? → AIF (Markov-blanketed inference); 4E (autopoietic coupling); CYB (goal-directed regulation).",
        ],
      },
      {
        heading: "Phase 2 — Test each candidate framework against the explanandum",
        intro: "Once you've identified the question, check what each framework offers and where it strains.",
        bullets: [
          "**AIF strain points**: phenomenal character (qualia), genuine novelty in cognition, conditions for Markov blanket existence (Aguilera 2022 critique).",
          "**4E strain points**: offline cognition (planning, memory, imagination) without internal representations; scaling from sensorimotor cognition to language and abstract thought.",
          "**PHE strain points**: intersubjective verification of phenomenological data; bridging first-person methodology to third-person science (the 'naturalizing phenomenology' project).",
          "**CYB strain points**: capturing the experiential and intentional aspects of mind that feedback alone doesn't address; explaining novelty within homeostatic frameworks.",
        ],
      },
      {
        heading: "Phase 3 — Look for convergence and divergence",
        bullets: [
          "**Convergence point**: autopoiesis. CYB (autopoietic systems as self-producing regulators), 4E (autopoiesis as biological foundation of enactivism), AIF (Markov-blanketed self-evidencing) all converge on self-producing systems as basic.",
          "**Divergence point**: representations. AIF requires generative models; 4E (radical reading) denies representations at basic cognition; CYB is agnostic; PHE rejects the question as ill-posed.",
          "**Divergence point**: phenomenal experience. PHE treats it as primary data; AIF tries to derive it from inference structure; 4E grounds it in embodiment; eliminativists deny it has the role we think it has.",
        ],
      },
      {
        heading: "Phase 4 — Pick metaphysical commitments explicitly",
        intro: "Mind questions inevitably hit metaphysical bedrock. Be explicit:",
        bullets: [
          "**Information realism (PCM)** → mind IS computation; consciousness is what some computations 'feel like.'",
          "**Process metaphysics (PRO)** → mind IS process; subjective form belongs to occasions of becoming.",
          "**Powers (POW)** → mind is the manifestation of mental powers / dispositions.",
          "**Substance (SUB) + dualism** → mind is a distinct substance or property of substances. Less popular today but logically available.",
          "**Critical Realism (CR)** → mind is an emergent stratum with its own causal powers; reducible to neither physics nor pure phenomenology.",
        ],
      },
      {
        heading: "Worked checklist for any mind-question",
        bullets: [
          "1. State the question in plain terms. What is the explanandum?",
          "2. Which of the four lenses (AIF, 4E, PHE, CYB) most natively addresses this kind of question?",
          "3. What does each OTHER framework have to say about it? (Use the Graph tab to see relationships.)",
          "4. Where do the frameworks converge — that's likely a robust feature.",
          "5. Where do they diverge — that's likely a genuine open question, not a calibration error.",
          "6. What metaphysical commitments are you making in your treatment?",
          "7. Are those commitments forced by the science, or chosen?",
        ],
      },
    ],
    closing: "Mind is the hardest case for any framework in this atlas because every framework here has something to say about it AND every framework misses something. The discipline is to keep all the lenses in view at once, refuse premature unification, and stay honest about what you're committing to.",
  },
  {
    id: "agentic-systems-workflow",
    title: "Agentic Systems — Cross-Substrate Workflow",
    intro: "How to do empirical research on agency that's actually publishable. The shape of the workflow is: pick a measure, pick at least two substrates, ensure the measurement is comparable, surrogate-test, and report substrate-specific divergences as findings rather than failures. See the Agents tab for the full conceptual ground and the ten worked proposals.",
    sections: [
      {
        heading: "Phase 1 — Pick a measure that's portable",
        intro: "Not every agency measure works across substrates. The portable ones share three properties: they don't require knowing the system's substrate, they have working implementations, and they have established surrogate-testing protocols.",
        bullets: [
          "**Krakauer's A\\* individuality** = I(S_{n+1}; S_n | E_n). Most portable. Light metaphysical baggage. Operationalised via PID estimators (Bertschinger et al.). Use for: brain regions, social agents, LLM ensembles.",
          "**ε-machine statistical complexity Cμ** (Crutchfield-Shalizi). Discovered structure, not assumed. CSSR algorithm. Use for: any symbolisable time series.",
          "**ΦID-causal-emergence** (Mediano-Rosas). Decomposes information into synergistic / redundant / unique. Code: ReconcilingEmergences toolbox. Use for: multi-variate time series with candidate macro-variables.",
          "**Semantic information** (Kolchinsky-Wolpert): scramble interventions, viability curves. Use for: systems where viability V is operationally definable.",
          "**Skip these for cross-substrate work** (without strong justification): variational free energy F (Markov blanket detection contested per Aguilera 2022); Φ (computationally expensive, conceptually contested per Aaronson 2014); assembly index (LZ-complexity critique per Abrahão et al. 2024).",
        ],
      },
      {
        heading: "Phase 2 — Pick at least two substrates with comparable data resolution",
        intro: "The biggest methodological trap is mismatched resolution. Comparing whole-brain BOLD to coarse macaque conflict scores will produce noise. Match the data carefully.",
        bullets: [
          "**Brain.** Public options: Human Connectome Project (HCP) fMRI; Allen Brain Atlas; OpenNeuro datasets. Parcellate to ~100-400 regions. Time series in TR units.",
          "**Society.** Public options: DeDeo-Krakauer-Flack macaque conflict data; Twitter cascade datasets; financial tick data (used by Park et al. 2007 for ε-machines).",
          "**AI agents.** Public options: Park et al. 2023 Generative Agents traces; CAMEL / AutoGen logs; SWE-Bench agent traces. You can also generate fresh data.",
          "**Resolution alignment.** Aim for ~10³-10⁵ time-step observations on ~10²-10³ unit dimensions per substrate. Anything less and information-theoretic estimators become unreliable.",
        ],
      },
      {
        heading: "Phase 3 — Estimator hygiene",
        intro: "All information-theoretic measures require careful estimation from finite data. Bad estimators produce significance where there is none.",
        bullets: [
          "**Always run shuffled-time-series surrogates.** Your measure should drop substantially on temporally shuffled data; if it doesn't, you're measuring marginal structure, not dynamics.",
          "**Always run partition-shuffled surrogates** when comparing groups. If a 'real' group and a randomly assembled group score equivalently, your measure isn't capturing groupness.",
          "**Use Bertschinger PID** for partial information decomposition; **PyPhi** for Φ; **CSSR** for ε-machines; **ReconcilingEmergences** for ΦID. Don't roll your own estimators without explicit calibration tests.",
          "**Report estimator bias.** Information measures are systematically biased upward at small N. Apply Marton–Shields blocking or NSB priors. Cite which correction you used.",
        ],
      },
      {
        heading: "Phase 4 — Cross-substrate analysis",
        intro: "This is where the agents-as-research-instruments framing pays off. The substrate differences ARE the findings.",
        bullets: [
          "**Compute the measure on each substrate independently.** Don't pool data across substrates — different noise structures will invalidate the comparison.",
          "**Compare distributions, not point estimates.** Bootstrap or jackknife confidence intervals on each substrate; report ranges.",
          "**Look for systematic divergences.** A finding that brain parcels and LLM ensembles have similar A\\* distributions is interesting. A finding that they diverge predictably is more interesting. A finding that one substrate has a phase transition the other doesn't is a publishable result.",
          "**Triangulate with a second measure.** If A\\* and ε-machine Cμ agree, you have convergent evidence. If they disagree, you've identified a case where the formal frameworks split — also publishable.",
        ],
      },
      {
        heading: "Phase 5 — Honesty about what you measured",
        bullets: [
          "Be explicit about which framework's definition of agency you're using. 'Agent' is not a single concept.",
          "If your measure gives positive results for a system you intuitively don't think is an agent (a thermostat, a Reed-Solomon decoder), report it. That's a result about the measure, not a flaw to hide.",
          "Don't claim your measure captures phenomenal experience, intentionality, or normativity unless your operationalisation tested for those specifically. The hard problem is hard and most measures don't touch it.",
          "Cite the critiques. A proposal that addresses Aguilera, Abrahão, or Aaronson head-on is stronger than one that ignores them.",
        ],
      },
      {
        heading: "Recommended sequence for a single researcher",
        bullets: [
          "**Month 1 (low-risk start).** Run P9 from the Agents tab: cross-framework concordance test on HCP fMRI or DeDeo macaque conflict. Compute A\\*, EI, Φ, Cμ on the same data. If correlations are weak, that's the finding.",
          "**Month 2-3.** Run P2: A\\* across the three substrates with publicly available data. Surrogate-test thoroughly.",
          "**Month 4+.** If P2 worked, escalate to P8: LLM ensembles as probes of agency phase transitions. Most original direction; needs the calibration P9 and P2 provide.",
        ],
      },
    ],
    closing: "The Agents tab gives the full conceptual ground and ten worked proposals. This methodology page gives the workflow to actually execute one. The single most actionable insight: most published agency work uses one measure on one substrate. A study that uses two measures on two substrates with proper surrogate testing is already at the frontier.",
  },
  {
    id: "high-traction-subset",
    title: "The High-Traction Subset — 7 Concepts You'll Use Weekly",
    intro: "Most concepts in this atlas are used occasionally. These seven you'll use constantly. Master these and you have 80% of practical leverage.",
    sections: [
      {
        heading: "1. Attractor / Basin",
        bullets: [
          "Almost any \"stuck\" system is in an undesirable basin.",
          "Most \"tipping points\" are basin transitions.",
          "Most \"stability\" is basin depth.",
        ],
      },
      {
        heading: "2. Feedback loop",
        bullets: [
          "Once you see loops, you can't unsee them.",
          "Most chronic problems are loop structure problems.",
          "Identify gain (high gain = small input → large output), direction (reinforcing or balancing), delay.",
        ],
      },
      {
        heading: "3. Coarse-graining / levels",
        bullets: [
          "The single most useful analytical move.",
          "Almost every \"intractable\" problem yields when you change levels.",
          "When stuck at one level, go up one level.",
        ],
      },
      {
        heading: "4. Mutual information",
        bullets: [
          "The basic quantitative measure of relatedness.",
          "When you suspect coupling but linear correlation is zero, compute MI.",
          "Necessary but not sufficient for causation.",
        ],
        formulas: [
          { f: "I(X;Y) = D_KL(p(x,y) ‖ p(x)p(y))", label: "Mutual information" },
        ],
      },
      {
        heading: "5. Path dependence",
        bullets: [
          "Most current state is more determined by trajectory than by current parameters.",
          "Asking \"why is X like this?\" almost always reveals path-dependent answers.",
          "QWERTY, x86, CUDA, cellular metabolism — all locked in by history.",
        ],
      },
      {
        heading: "6. Markov blanket / boundary",
        bullets: [
          "What is and isn't part of this system?",
          "The blanket determines what you can intervene on with predictable effects.",
          "Caveat: many real systems have no clean blanket (Aguilera 2022).",
        ],
      },
      {
        heading: "7. Phase transition / bifurcation",
        bullets: [
          "Where regime changes happen.",
          "Identifying nearby critical points warns you about instability.",
          "Identifying distant ones tells you the regime is robust.",
        ],
      },
      {
        heading: "Learning order",
        bullets: [
          "**First**: master attractors and feedback loops. They give you 80% of practical leverage.",
          "**Next**: add coarse-graining when you start hitting problems where the level matters.",
          "**Then**: add MI when correlation fails.",
          "**Finally**: add the rest as the analytical pressure builds.",
        ],
      },
    ],
  },
];

// ─── EXERCISES ────────────────────────────────────────────────────────────────
const EXERCISES = [
  {
    title: "Exercise 1 — Stocks and Flows of Your Day",
    goal: "Develop reflexive stock/flow recognition.",
    steps: [
      "List 5 stocks in your daily life (energy, focus, money, relationships, knowledge, sleep debt, attention budget).",
      "For each, name 2 inflows and 2 outflows.",
      "Identify which flow is the current bottleneck.",
      "Note: the bottleneck is rarely where you assume.",
    ],
    insight: "Common discovery — people working on 'energy management' typically restrict the outflow when the real bottleneck is on the inflow side (sleep, recovery, food).",
  },
  {
    title: "Exercise 2 — Find the Feedback Loop",
    goal: "Stop diagnosing recurring problems at the event level.",
    steps: [
      "Pick something that frustratingly persists despite effort to change it.",
      "Map: stock → intervention that should reduce it → what reinforces it instead → why the system snaps back.",
      "Identify whether the dominant loop is reinforcing or balancing.",
      "Identify the loop's gain (high gain = small input → large output).",
    ],
    insight: "Most 'willpower problems' are feedback structure problems. Most 'communication problems' are delay problems.",
  },
  {
    title: "Exercise 3 — Identify the Right Scale",
    goal: "Stop trying to solve problems at the wrong level.",
    steps: [
      "Pick a problem you're currently working on (technical, organizational, personal).",
      "Describe it at three scales: most micro (individual actions/states), middle (patterns/processes), most macro (paradigm/system identity).",
      "For each scale, ask: where does intervention here actually change outcomes? Where is it just symptom-treatment?",
      "Identify the scale at which the leverage actually lives — usually NOT the scale at which the symptom is most visible.",
    ],
    insight: "Most analytical failures are level-mismatches. The problem is visible at one scale but lives at another.",
  },
  {
    title: "Exercise 4 — Run the Coarse-Graining Test",
    goal: "Distinguish real macro patterns from convenient redescriptions.",
    steps: [
      "Pick a system you understand well (a team, a codebase, an ecosystem, an economy).",
      "Identify a candidate macro variable (team productivity, code health, ecosystem state, GDP).",
      "Test: does this macro variable PREDICT outcomes that micro variables don't predict as well? (CM-style test.)",
      "Test: do interventions on this macro variable produce more reliable effects than interventions on micro variables? (CE-style test.)",
      "Yes to both → real macro pattern. Yes to one → useful but contestable. No to both → window-dressing.",
    ],
    insight: "Many widely-used 'macro' concepts in organizations and policy fail both tests.",
  },
  {
    title: "Exercise 5 — Find the Markov Blanket",
    goal: "Rigorously identify what individuates a system.",
    steps: [
      "Pick a system whose identity you take for granted (yourself, your company, your relationship, your country).",
      "List the variables that, if you knew them, would make the rest of the world conditionally independent of the system's internal state.",
      "Test: are these variables actually the boundary? Or are there leaks (variables outside the blanket that still influence internal state)?",
      "If there are leaks, the system is more permeable than it appears — the apparent boundary is performative, not statistical.",
    ],
    insight: "Most 'boundaries' are leakier than people think. Most 'systems' are less statistically individuable than their performative identity suggests. Cf. Aguilera et al. 2022 — blanket non-uniqueness is common.",
  },
  {
    title: "Exercise 6 — Locate the Leverage Point",
    goal: "Stop intervening at the lowest-leverage points by default.",
    steps: [
      "Take any system you want to change. Walk Meadows's leverage ladder from low to high (see formula box).",
      "Identify which level your current interventions operate on.",
      "Identify the highest level where you have plausible access.",
      "Move one level up and try again.",
    ],
    leverage_ladder: [
      "Parameters (lowest)     — numerical settings, budgets",
      "Flows                   — rates of accumulation / depletion",
      "Stocks                  — the buffers themselves",
      "Feedback structure      — which loops exist, with what gain",
      "Rules                   — incentives, permissions, constraints",
      "Goals                   — what the system is FOR",
      "Self-organization       — ability to evolve its own structure",
      "Paradigm                — the worldview generating the rules",
      "Transcend paradigms     — (highest)",
    ],
    insight: "Concrete example — trying to lose weight by counting calories (parameter) vs. restructuring food access at home (rules) vs. changing what you eat for (paradigm).",
  },
  {
    title: "Exercise 7 — Translate Across All Frameworks",
    goal: "Force translation across frameworks to expose what each one adds.",
    steps: [
      "Pick a system you're actively analyzing.",
      "Describe it in each productive framework's language — see the framework checklist below.",
      "Note where multiple frameworks converge → that's a real feature of the system.",
      "Note where they diverge → that's a genuinely open question.",
      "Open the Graph tab to see which frameworks are most closely related, which ground which, which oppose each other.",
    ],
    framework_checklist: [
      "**PC (Dynamical Systems)**: What are the state variables, attractors, basins, bifurcation parameters?",
      "**IT (Information Theory)**: What are the relevant joint distributions, mutual informations, transfer entropies?",
      "**CM (Computational Mechanics)**: What would the ε-machine look like? What is Cμ?",
      "**CI (Causal Inference)**: What's the causal graph? Which edges are testable by intervention?",
      "**CE (Causal Emergence)**: At what scale is EI maximized? Is there a causally privileged level?",
      "**AIF (Active Inference)**: Where's the Markov blanket — if there is one? What is the agent inferring?",
      "**EVO (Evolutionary Dynamics)**: Is this system evolving? Variation + heritability + differential fitness?",
      "**NET (Network Science)**: What's the graph topology? Modularity? Degree distribution?",
      "**TH (Stochastic Thermodynamics)**: What's driven? What's dissipating? Where's the entropy production?",
      "**AT (Assembly Theory)**: What's the assembly index of the objects produced? Copy number?",
    ],
    insight: "Where frameworks converge, you've likely identified a real feature. Where they diverge, you've identified a question worth pursuing.",
  },
  {
    title: "Exercise 8 — Pick Your Metaphysics Explicitly",
    goal: "Make your implicit ontological commitments explicit.",
    steps: [
      "Pick a question or system you've been analyzing.",
      "Ask: 'What kind of thing is this question about — substances? processes? powers? mechanisms? layered structures?'",
      "Read each of the 5 metaphysical framework descriptions (Frameworks tab → Metaphysical Systems).",
      "Identify the framework you've been using implicitly.",
      "Identify the framework that would best fit the question — they may differ.",
      "Note the controversies. The framework you choose has live disputes; you're committing to a side whether you know it or not.",
    ],
    insight: "Most working scientists default to mechanism (MEC) + substance metaphysics (SUB) without realizing it. For some questions (origin of life, evolutionary novelty, agency) process (PRO) or powers (POW) ontology is a far better fit. The choice is consequential.",
  },
];

// ─── AGENTIC SYSTEMS DATA ─────────────────────────────────────────────────────
// Cross-framework definitions of "agent", substrate applications, research proposals.
// Anchored in the research document on agents-as-research-instruments across
// brain, society, and AI substrates.

const AGENT_DEFINITIONS = [
  {
    fw: "aif", label: "Active Inference / FEP",
    minimal: "A random dynamical system at non-equilibrium steady state with a Markov blanket partition (η, s, a, μ) and non-zero solenoidal flow on internal states.",
    formal: "Internal states μ parametrise a variational density q(η) that minimises F = E_q[ln q(η) − ln p(s, η)]; conditional independence p(μ, η | s, a) = p(μ | s, a) p(η | s, a).",
    operational: "Detect Markov blankets via conditional-independence tests on time series; ascribe variational inference to internal states.",
    status: "Mature theoretically; technically contested (see Aguilera et al. 2022; Biehl et al. 2021).",
    requires: { boundary: true, predicts: true, normativity: false, replication: false, coarseGrain: false, code: true },
  },
  {
    fw: "cyb", label: "Cybernetic / Conant-Ashby",
    minimal: "A regulator R whose optimal control of system S requires R to be homomorphic to S — every good regulator must internally model what it regulates.",
    formal: "Under information-bottleneck constraint, optimal regulator achieves zero conditional entropy of outcomes given regulator states by mirroring system structure (Conant & Ashby 1970; Wentworth's 2021 reformulation).",
    operational: "Test whether observed regulators contain reduced-dimension models of regulated systems.",
    status: "Classic; recently reformulated for rigor.",
    requires: { boundary: false, predicts: true, normativity: false, replication: false, coarseGrain: false, code: true },
  },
  {
    fw: "e4", label: "Enactivism (Varela, Di Paolo)",
    minimal: "An autopoietic system that (i) maintains its own organisation through operational closure, (ii) is adaptive (capable of biased coupling), (iii) is the source of normative perspectives.",
    formal: "Three conditions for sensorimotor agency (Barandiaran, Di Paolo & Rohde 2009): individuality, interactional asymmetry, normativity.",
    operational: "No fully formal operationalisation; case-by-case identification of self-producing systems.",
    status: "Philosophically developed; weakly formalised. Di Paolo et al. 2022 explicitly diverges from FEP.",
    requires: { boundary: true, predicts: false, normativity: true, replication: false, coarseGrain: false, code: false },
  },
  {
    fw: "cm", label: "Computational Mechanics",
    minimal: "A stochastic process whose ε-machine — the unique minimal sufficient predictor — has non-trivial causal-state structure.",
    formal: "Causal states: [s] ~ [s'] iff P(future | s) = P(future | s'). Statistical complexity Cμ = H[S] measures retained memory; excess entropy E = I(past; future) measures predictability.",
    operational: "CSSR algorithm (Shalizi & Klinkner 2004) reconstructs ε-machines from symbolised time series.",
    status: "Mature, code available, applied to EEG (Nehaniv & Antonova 2017) and markets (Park et al. 2007).",
    requires: { boundary: false, predicts: true, normativity: false, replication: false, coarseGrain: false, code: true },
  },
  {
    fw: "ce", label: "Causal Emergence (Hoel)",
    minimal: "A system whose effective information EI is maximised at a coarse-grained macro-scale — implying the macro-variable is causally privileged.",
    formal: "EI = log N − H(E | I_D) under maximum-entropy do-distribution; CE detected when EI(macro) > EI(micro).",
    operational: "Mediano-Rosas ReconcilingEmergences toolbox; Klein-Hoel network EI; NIS+ for automatic macro-variable discovery.",
    status: "Code available; validated on brain data, Game of Life, flocking boids.",
    requires: { boundary: false, predicts: false, normativity: false, replication: false, coarseGrain: true, code: true },
  },
  {
    fw: "at", label: "Assembly Theory",
    minimal: "A system producing high-assembly-index objects in high copy number — Assembly = A × N.",
    formal: "A(x) = min joining steps to build x from primitives, allowing reuse; N(x) = observed abundance.",
    operational: "Mass spectrometry for chemistry; graph counts for technology.",
    status: "Empirically deployed for biosignatures; algorithmic-complexity critique unresolved (Abrahão et al. 2024).",
    requires: { boundary: false, predicts: false, normativity: false, replication: true, coarseGrain: false, code: true },
  },
  {
    fw: "con", label: "Constructor Theory",
    minimal: "An entity that can cause a task to occur while retaining the ability to cause it again — a programmable constructor.",
    formal: "Marletto (2015): self-reproduction and natural selection possible under no-design laws given digital information.",
    operational: "Mostly conceptual; few empirical applications.",
    status: "Programmatic; small research community.",
    requires: { boundary: false, predicts: false, normativity: false, replication: false, coarseGrain: false, code: false },
  },
  {
    fw: "it", label: "Information-Theoretic Individuality (Krakauer et al.)",
    minimal: "A system whose next-state retains conditional dependence on its own past given the environment: A* = I(S_{n+1}; S_n | E_n) > 0.",
    formal: "Decomposition I(S_n, E_n; S_{n+1}) = I(S_{n+1}; S_n) + I(S_{n+1}; E_n | S_n). Three regimes: organismal (A* dominant), colonial (total temporal coherence), driven (environment dominant).",
    operational: "Bertschinger PID estimators; surrogate-test via shuffled partitions.",
    status: "Theory clear (Krakauer et al. 2020); empirical applications limited; the cleanest cross-framework measure.",
    requires: { boundary: true, predicts: true, normativity: false, replication: false, coarseGrain: false, code: true },
  },
  {
    fw: "it", label: "Semantic Information (Kolchinsky-Wolpert)",
    minimal: "The subset of syntactic information whose erasure via scrambling interventions reduces viability V.",
    formal: "Scramble agent-environment correlations with graded severity; plot V vs. syntactic information retained; semantic info is the inflection point.",
    operational: "Tested on resource-foraging agents (Sowinski et al. 2023) and bacterial chemotaxis.",
    status: "Theory + implementations exist; ripe for LLM-agent extension.",
    requires: { boundary: true, predicts: true, normativity: true, replication: false, coarseGrain: false, code: true },
  },
  {
    fw: "it", label: "Integrated Information Theory (Tononi)",
    minimal: "A system with Φ > 0 — informational integration irreducible to its parts.",
    formal: "Φ = min_π D_KL(p ‖ p_π) over system partitions π.",
    operational: "PyPhi software; computationally expensive (exponential in subsystem size).",
    status: "Heavily contested. Aaronson's 2014 critique demonstrates large Reed-Solomon decoders score arbitrarily high Φ.",
    requires: { boundary: false, predicts: false, normativity: false, replication: false, coarseGrain: false, code: true },
  },
];

// Substrate × framework grid — what's been done across brains, societies, AI agents.
// status: "done" = published applications exist; "partial" = related work; "open" = obvious gap
const AGENT_SUBSTRATE_GRID = [
  // BRAIN
  { fw: "cm", substrate: "brain", status: "partial", note: "Nehaniv & Antonova 2017 applied ε-machine reconstruction to EEG microstate sequences — closest precedent for the 'ε-machines per brain region' direction." },
  { fw: "aif", substrate: "brain", status: "done", note: "Friston, Fagerholm, Razi et al. 2021 'Parcels and particles' formalises recursive Markov-blanket discovery for brain parcellation." },
  { fw: "ce", substrate: "brain", status: "done", note: "Hoel et al.; NIS+ (Zhang et al. 2023): 'NIS+ demonstrated ability to automatically find emergent macro-variables in real brain data.' Luppi-Mediano-Rosas use ΦID on fMRI/MEG." },
  { fw: "it", substrate: "brain", status: "partial", note: "IIT-based Φ computations on brain networks (Kim & Lee 2019); A* not yet applied to brain parcels." },
  { fw: "th", substrate: "brain", status: "open", note: "Still-Sivak-Crooks 'thermodynamics of prediction' bound applies to neural computation but rarely operationalised on data." },
  { fw: "at", substrate: "brain", status: "open", note: "No published assembly-theory application to neural systems." },

  // SOCIETY
  { fw: "cm", substrate: "society", status: "done", note: "Park et al. 2007 reconstruct ε-machines from S&P 500 tick data, find statistical complexity declined over 20 years. DeDeo 2013 on Wikipedia edits." },
  { fw: "ce", substrate: "society", status: "partial", note: "Klein-Hoel 2020 networks framework applicable; social-network case studies thin." },
  { fw: "aif", substrate: "society", status: "partial", note: "Veissière et al. 2020 'Thinking through other minds'; Albarracin et al. 2025 formalise group-level Markov blankets. Bruineberg et al. 2022 critique: blankets are diffuse for groups." },
  { fw: "it", substrate: "society", status: "partial", note: "DeDeo-Krakauer-Flack inductive game theory on macaque conflict; Krakauer A* designed cross-scale but rarely applied to actual social data." },
  { fw: "evo", substrate: "society", status: "done", note: "Cultural evolution; institutional dynamics; long-established literature." },
  { fw: "at", substrate: "society", status: "open", note: "Technology-evolution applications proposed but not systematically tested." },

  // AI / DESIGNED AGENTS
  { fw: "aif", substrate: "ai", status: "partial", note: "Prakki 2024 (arXiv:2412.10425) implements AIF cognitive layer for LLM agents; Friedman et al. 2025 'Orchestrator' uses VFE for multi-agent coordination." },
  { fw: "cm", substrate: "ai", status: "open", note: "No published ε-machine analysis of LLM-agent behavior — obvious gap." },
  { fw: "ce", substrate: "ai", status: "open", note: "Causal emergence on multi-LLM systems unstudied; Park et al. 2023 'Generative Agents' provides target data." },
  { fw: "it", substrate: "ai", status: "partial", note: "Sowinski et al. 2023 apply semantic information to resource-foraging agents; no application to current LLM agents." },
  { fw: "at", substrate: "ai", status: "open", note: "Assembly-theoretic analysis of AI-generated code/protocols proposed; not yet done." },
  { fw: "th", substrate: "ai", status: "partial", note: "LLM inference energetics measured; not yet connected to Still-Sivak-Crooks predictive bounds." },
];

// Ten cross-framework research proposals
const AGENT_PROPOSALS = [
  {
    id: "P1",
    title: "ε-machine signatures of brain functional areas",
    frameworks: ["cm", "it"],
    substrates: ["brain"],
    summary: "Apply CSSR (Shalizi & Klinkner 2004) to symbolised intracranial EEG, BOLD parcel time series, and microstate sequences. Compute statistical complexity Cμ, entropy rate hμ, and excess entropy E per parcel.",
    hypothesis: "Parcels in canonical functional networks (DMN, salience, attention) cluster in (Cμ, hμ) space; clinical populations show shifted distributions.",
    falsification: "If parcel ε-machines are indistinguishable from autoregressive surrogates, the hypothesis fails.",
    code: "CSSR (bactra.org); finite-sample corrections via Marton–Shields blocking.",
    risk: "Medium — data exists, method exists, surrogate testing is hard.",
  },
  {
    id: "P2",
    title: "A* individuality across the three substrates",
    frameworks: ["it"],
    substrates: ["brain", "society", "ai"],
    summary: "Apply Krakauer A* = I(S_{n+1}; S_n | E_n) to (a) fMRI ROIs with rest-of-brain as E, (b) macaque/Twitter agents with group as E, (c) LLM agents in multi-agent simulation with collective as E.",
    hypothesis: "'Real' agents (stable-function parcels, dominant macaques, well-prompted LLMs) score higher A* than random partitions; A*/(A* + I(S_{n+1}; E_n | S_n)) discriminates organismal from driven.",
    falsification: "If A* is indistinguishable across structurally different systems, individuality is not capturing the intended signal.",
    code: "Bertschinger PID estimators; pyphi for related measures.",
    risk: "Medium — main bottleneck is joint-distribution estimation at high dimensionality.",
    priority: true,
  },
  {
    id: "P3",
    title: "Causal emergence as a substrate-comparison probe",
    frameworks: ["ce", "it"],
    substrates: ["brain", "society", "ai"],
    summary: "Run Mediano-Rosas ReconcilingEmergences on matched-resolution time series from brain parcellation, social-interaction networks, and LLM-agent logs (e.g. Park et al. 2023 Generative Agents).",
    hypothesis: "The location AND magnitude of ΦID-causal-emergence is substrate-specific: largest for brain parcels, moderate for tight social groups, smallest for current LLM collectives.",
    falsification: "If LLM swarms show ΦID-emergence comparable to brains, that itself is a major empirical claim.",
    code: "ReconcilingEmergences toolbox (open source).",
    risk: "Low-medium — code exists, target data exists.",
  },
  {
    id: "P4",
    title: "Markov blanket topology comparison across substrates",
    frameworks: ["aif", "net"],
    substrates: ["brain", "society", "ai"],
    summary: "Implement Friston-Fagerholm-Razi 2021 recursive eigenstate-based blanket detection on brain parcels, social interaction graphs, and LLM-agent communication graphs. Compare blanket-graph statistics.",
    hypothesis: "Brain blanket-graphs deeper and more modular; social shallower; LLM-agent highly modular but shallow.",
    falsification: "If blanket detection fails to identify intuitive agents (as Aguilera 2022 critique implies), the proposal also tests the critique empirically.",
    code: "Custom implementation of Friston 2021 pipeline.",
    risk: "High — Aguilera/Biehl critiques may invalidate the underlying method.",
  },
  {
    id: "P5",
    title: "Semantic-information scrambling for LLM agents",
    frameworks: ["it"],
    substrates: ["ai"],
    summary: "Build a multi-LLM agent system on a long-horizon benchmark (SWE-Bench, AgentBench). Apply graded scrambling to agent-environment correlations, inter-agent communication, and internal context. Plot viability V vs retained syntactic information.",
    hypothesis: "Semantic-information fraction differs systematically across agentic LLMs, human teams, and animal collectives — enabling quantitative cross-substrate meaning comparison.",
    falsification: "If V degrades linearly with all scrambling (no inflection), there's no semantic-syntactic distinction.",
    code: "Custom; uses existing benchmark harnesses.",
    risk: "Medium — engineering-heavy but conceptually clean.",
  },
  {
    id: "P6",
    title: "Assembly-theoretic agency signatures for evolving AI",
    frameworks: ["at"],
    substrates: ["ai"],
    summary: "Compute assembly index for (a) AI-generated code over time, (b) AI architecture diversity, (c) emergent multi-agent communication protocols.",
    hypothesis: "A × N grows superlinearly when AI systems pass an 'innovation threshold' — analogous to Walker-Cronin's biosignature boundary at A ≈ 15.",
    falsification: "Test whether AT adds discriminative power over LZ compression (per Abrahão et al. 2024 critique).",
    code: "Open assembly-index calculators.",
    risk: "Medium-high — AT critique may invalidate the conceptual baseline.",
  },
  {
    id: "P7",
    title: "Thermodynamic cost of agency across substrates",
    frameworks: ["th"],
    substrates: ["brain", "society", "ai"],
    summary: "Use Still-Sivak-Bell-Crooks 2012 nostalgia-dissipation bound. Compute nostalgia for cortical predictive coding (existing models), social-network forecasting (trading firms), and LLM inference (token-level entropy + measured energy).",
    hypothesis: "Slope of nostalgia-vs-dissipation differs across substrates and correlates with task efficiency.",
    falsification: "If thermodynamic bounds give substrate-independent identical slopes, the constraint is universal not biology-specific.",
    code: "Custom; depends on energy-instrumented inference.",
    risk: "High — requires precision energy measurement.",
  },
  {
    id: "P8",
    title: "Agents-as-research-instruments: LLM ensembles as phase-transition probes",
    frameworks: ["it", "aif"],
    substrates: ["ai"],
    summary: "Use LLM-agent populations as experimental systems. Parametrically vary number, bandwidth, shared context, goal alignment. Measure individuality (A*), integrated information (Φ), and Markov-blanket emergence.",
    hypothesis: "There exist threshold parameter values where collective LLM behavior crosses individuality / integration / blanket-emergence boundaries — directly observable.",
    falsification: "If measures vary smoothly with no phase structure, LLM ensembles don't exhibit threshold dynamics.",
    code: "CAMEL/AutoGen + custom measurement layer.",
    risk: "High — most original direction; no clear precedent; novel framework needed.",
    priority: true,
  },
  {
    id: "P9",
    title: "Cross-framework concordance test on one dataset",
    frameworks: ["it", "aif", "ce", "cm"],
    substrates: ["brain", "society"],
    summary: "On a single dataset (HCP fMRI or DeDeo macaque conflict), compute A*, EI, Φ, ε-machine Cμ, and ΦID-emergence at matched resolution and parcellation.",
    hypothesis: "These measures should be at least weakly correlated for 'real' agents. If essentially independent, agency is multiply realisable in formal definitions with NO shared substrate.",
    falsification: "Negative result (zero correlation) is itself the most important publishable finding — it would force the field to choose between frameworks rather than treating them as complementary.",
    code: "PyPhi, ReconcilingEmergences, CSSR, custom A* estimator.",
    risk: "Low — definitive either way.",
    priority: true,
  },
  {
    id: "P10",
    title: "Constructor-theoretic decomposition of LLM-agent tasks",
    frameworks: ["con"],
    substrates: ["ai"],
    summary: "Annotate corpus of agentic LLM task traces (HumanEval, SWE-Bench) with constructor-theoretic primitives: tasks performed, substrates transformed, constructor preserved.",
    hypothesis: "Task-completion factorises into Marletto-style possible/impossible task graphs; success rate correlates with constructor-theoretic interoperability of subtasks.",
    falsification: "If task decompositions yield no predictive power, constructor theory adds no value here.",
    code: "Mostly conceptual / annotation.",
    risk: "High — most speculative; mostly a conceptual contribution.",
  },
];

const AGENT_COMPARATIVE = [
  {
    pair: "brain ↔ society",
    shared: "Small-world topology, modular organisation, criticality, scale-free degree distributions. Both analysable by ε-machines (Nehaniv-Antonova for brain; Park et al. and DeDeo for society) and causal emergence. Flack-Krakauer 'collective computation' explicitly treats both via shared statistical-complexity language.",
    divergent: "Brains have strict spatial embedding and metabolic constraints; social networks have variable bandwidth, asynchronous communication, explicit goal misalignment between members.",
  },
  {
    pair: "brain ↔ AI",
    shared: "Connectionist substrates that learn from data; predictive coding (cortex) or autoregressive prediction (LLMs); hierarchical organisation.",
    divergent: "Brains have embodied sensorimotor loops, basal-metabolism energy budgets, slow timescales. LLM agents are static between updates, lack persistent memory across sessions without scaffolding, lack metabolic constraint. Sharp claim: LLMs cannot close the AIF perception-action loop because weights don't update during a session.",
  },
  {
    pair: "society ↔ AI",
    shared: "Multi-agent systems with communication, coordination, emergent collective behaviour. Active-inference formulations treat both as nested generative models. Park et al. 2023 demonstrates explicit social LLM behaviour (forming opinions, scheduling meetings, spreading news).",
    divergent: "Human societies have norm-establishing institutions, embodied trust, reproductive continuity. LLM societies are stateless, lack biological lineage, lack stable institutional structure beyond what's prompted.",
  },
];

const AGENT_CRITIQUES = [
  {
    target: "Free Energy Principle / Markov blankets",
    critics: "Aguilera, Millidge, Tschantz & Buckley 2022 (Phys. Life Rev. 40); Biehl, Pollock & Kanai 2021 (Entropy 23: 293); Bruineberg, Dołęga, Dewhurst & Baltieri 2022 (BBS)",
    point: "Markov blanket condition only holds for narrow parameter regimes in coupled stochastic systems. The 'free energy lemma' has explicit counterexamples. Blankets are diffuse for social systems. Defenders (Friston et al. 2023) reformulate via path integrals; debate ongoing.",
  },
  {
    target: "Assembly Theory",
    critics: "Abrahão, Uthamacumaran, Hernández-Orozco, Kiani, Tegnér & Zenil 2024 (PLOS Complex Systems 1: e0000014)",
    point: "AT is an approximation to LZ algorithmic complexity that 'does not lead to an explanation or quantification of biases in generative processes that could not have been arrived at using Shannon Entropy.' Walker-Cronin response defends the empirical biosignature finding but doesn't directly address the algorithmic-complexity critique.",
  },
  {
    target: "Integrated Information Theory",
    critics: "Aaronson 2014 (Shtetl-Optimized); Cerullo 2015 (PLOS Comp. Biol. 11: e1004286); Merker, Rudrauf & Williford 2022 (BBS)",
    point: "Large Reed-Solomon decoders score arbitrarily high Φ — Tononi accepts this implication, critics consider it a reductio. IIT lacks justification for its information-exclusion principle. Φ may measure global information-transfer efficiency rather than consciousness.",
  },
  {
    target: "Causal Emergence (Hoel)",
    critics: "Dewhurst 2021 (Thought); Eberhardt-style critiques",
    point: "EI is computed under a uniform max-entropy do() distribution — an artefact of the choice of intervention measure. Comolatti-Hoel 2022 defends robustness across many measures but concedes prior-dependence.",
  },
  {
    target: "Estimator pessimism (all measures)",
    critics: "Methodological literature on PID, MI estimators",
    point: "All information-theoretic agency measures (A*, Φ, EI, ΦID, semantic info) require accurate joint-distribution estimation from finite data. For high-dimensional substrates (whole-brain BOLD, LLM ensembles with rich state), this is a serious bottleneck. Methods exist but have not been stress-tested at the scales these proposals require.",
  },
  {
    target: "Pancomputationalism trivialization",
    critics: "Putnam, Searle",
    point: "If 'every physical system computes,' then ε-machine inference reveals nothing distinctive about agents — every system has some causal-state structure. The non-trivial empirical claim is that agentic systems have STRUCTURED ε-machines with high statistical complexity AND high A*, not merely non-trivial ones.",
  },
];


const LEARNING_PATH = [
  {
    phase: "Weeks 1–2",
    title: "Foundation — Dynamical Systems Thinking",
    text: "Read Meadows, Thinking in Systems. Get the vocabulary: stocks, flows, feedback loops, delays, attractors, leverage points. Identify these in real systems you know. Do Exercises 1, 2.",
  },
  {
    phase: "Weeks 3–4",
    title: "Information Theory",
    text: "Read Shannon's 1948 paper (still the clearest introduction). Then Cover & Thomas, Elements of Information Theory, chapters 2–4: entropy, mutual information, channel capacity. Add Schreiber 2000 for transfer entropy. Practice computing MI on toy distributions.",
  },
  {
    phase: "Weeks 5–6",
    title: "Causal Inference",
    text: "Read Pearl, The Book of Why (intuitive) or Causality (technical). Learn the three-rung ladder, do-calculus, backdoor criterion. Practice drawing causal DAGs for real situations. Do Exercise 7 with a focus on the CI framework.",
  },
  {
    phase: "Weeks 7–8",
    title: "Multi-Scale Structure & Emergence",
    text: "Read Hoel's 2013 PNAS paper on causal emergence. Read Crutchfield's 'Between Order and Chaos' (Nature Physics 2012). Do Exercises 3, 4 to develop scale-identification skills.",
  },
  {
    phase: "Weeks 9–10",
    title: "Evolutionary Dynamics & Networks",
    text: "Read Nowak, Evolutionary Dynamics (chapters 1–4 for replicator equation, ESS, Price equation). Read Barabási, Network Science (free online textbook) for degree distributions, modularity, percolation. These two frameworks unlock most biology and most social-system applications.",
  },
  {
    phase: "Weeks 11–12",
    title: "Thermodynamics & Active Inference",
    text: "Read Seifert 2012 review of stochastic thermodynamics for Jarzynski, Crooks, fluctuation theorems. Then Parr, Pezzulo & Friston, Active Inference (MIT Press 2022). Approach FEP skeptically: ask which claims are mathematical, which empirical, which speculative.",
  },
  {
    phase: "Weeks 13–14",
    title: "Metaphysical Commitments",
    text: "Read Ladyman & Ross, Every Thing Must Go (SR). Then choose one rival: Mumford & Anjum, Getting Causes from Powers (POW); or Dupré & Nicholson, Everything Flows (PRO); or Bhaskar, A Realist Theory of Science (CR). Do Exercise 8 to surface your own implicit ontology.",
  },
  {
    phase: "Weeks 15+",
    title: "Application & Synthesis",
    text: "Pick one real system you understand intimately. Apply every framework. Identify where they converge, diverge, illuminate, mislead. Use the Graph tab to navigate the relationships. The exercise of forced application is what reveals what each framework is actually good for. Re-read the Micro ↔ Macro synthesis method.",
  },
];

const BOOKS = [
  // Foundation
  { name: "Thinking in Systems", author: "Donella Meadows", year: "2008", note: "The foundation. Read first.", category: "foundation" },
  { name: "Nonlinear Dynamics and Chaos", author: "Steven Strogatz", year: "2014", note: "Standard textbook for dynamical systems.", category: "foundation" },
  // Information
  { name: "Elements of Information Theory", author: "Cover & Thomas", year: "2006", note: "Standard reference for Shannon IT.", category: "information" },
  { name: "An Introduction to Kolmogorov Complexity", author: "Li & Vitányi", year: "2019", note: "AIT canonical reference.", category: "information" },
  // Causation
  { name: "The Book of Why", author: "Pearl & Mackenzie", year: "2018", note: "Intuitive causal inference.", category: "causation" },
  { name: "Causality", author: "Judea Pearl", year: "2009", note: "Technical SCM + do-calculus.", category: "causation" },
  // Multi-scale / Emergence
  { name: "Between Order and Chaos", author: "Crutchfield", year: "2012", note: "Computational mechanics primer (Nature Physics).", category: "scale" },
  { name: "The World Behind the World", author: "Erik Hoel", year: "2023", note: "Accessible introduction to causal emergence.", category: "scale" },
  // Evolution
  { name: "Evolutionary Dynamics", author: "Martin Nowak", year: "2006", note: "Mathematical evolutionary theory.", category: "evolution" },
  { name: "The Major Transitions in Evolution", author: "Maynard Smith & Szathmáry", year: "1995", note: "Reorganizations of evolutionary individuality.", category: "evolution" },
  // Networks
  { name: "Network Science", author: "Albert-László Barabási", year: "2016", note: "Free online textbook. The standard.", category: "networks" },
  { name: "Sync", author: "Steven Strogatz", year: "2003", note: "Accessible synchronization + network dynamics.", category: "networks" },
  // Thermodynamics
  { name: "Order Out of Chaos", author: "Prigogine & Stengers", year: "1984", note: "Dissipative structures, qualitative.", category: "thermo" },
  { name: "Stochastic Thermodynamics review", author: "Udo Seifert", year: "2012", note: "Reports on Progress in Physics — the technical entry point.", category: "thermo" },
  // Active Inference
  { name: "Active Inference", author: "Parr, Pezzulo & Friston", year: "2022", note: "Clean FEP introduction (MIT Press).", category: "aif" },
  // Assembly Theory
  { name: "Assembly Theory papers", author: "Walker, Cronin et al.", year: "2017–2023", note: "Start with Marshall et al. 2017, then Walker et al. Nature 2023.", category: "assembly" },
  // Metaphysics — structural realism
  { name: "Every Thing Must Go", author: "Ladyman & Ross", year: "2007", note: "Ontic structural realism — the SR anchor.", category: "metaphysics" },
  { name: "Real Patterns", author: "Daniel Dennett", year: "1991", note: "The pattern-realism criterion (paper, freely available).", category: "metaphysics" },
  // Metaphysics — powers
  { name: "Getting Causes from Powers", author: "Mumford & Anjum", year: "2011", note: "Dispositionalism applied to causation.", category: "metaphysics" },
  { name: "Nature's Metaphysics", author: "Alexander Bird", year: "2007", note: "Dispositional essentialism — properties as powers.", category: "metaphysics" },
  // Metaphysics — process
  { name: "Everything Flows", author: "Dupré & Nicholson (eds.)", year: "2018", note: "Process biology — modern process philosophy applied.", category: "metaphysics" },
  { name: "Process and Reality", author: "Whitehead", year: "1929", note: "The classical statement. Difficult; pair with a secondary source.", category: "metaphysics" },
  // Metaphysics — mechanism, CR
  { name: "In Search of Mechanisms", author: "Carl Craver & Lindley Darden", year: "2013", note: "New Mechanism applied to biology.", category: "metaphysics" },
  { name: "A Realist Theory of Science", author: "Roy Bhaskar", year: "1975", note: "Critical Realism — stratified ontology.", category: "metaphysics" },
];

// ════════════════════════════════════════════════════════════════════════════
// REACT COMPONENT
// ════════════════════════════════════════════════════════════════════════════
// ─── PRIMITIVES TAB ──────────────────────────────────────────────────────────
const P_SYM  = "#60a5fa";
const P_ASYM = "#f59e0b";
const P_BOTH = "#a78bfa";
const P_EMRG = "#34d399";
const PSTREAM_COLOR = { sym: P_SYM, asym: P_ASYM, both: P_BOTH, emergent: P_EMRG };
const PSTREAM_LABEL = { sym: "Distinction stream", asym: "Asymmetry stream", both: "Requires both", emergent: "Emergent" };

// Consensus / Contested badges — used by both Primitives and System Types tabs
const STATUS_COLOR = {
  "consensus":             "#5dcaa5",   // green — widely accepted
  "atlas-position":        "#fbbf24",   // amber — defensible but one of several
  "contested":             "#ef4444",   // red — active debate
  "placeholder":           "#94a3b8",   // grey — formal placeholder, no natural instance
  "modeling-abstraction":  "#94a3b8",   // grey — useful idealization, not a level of being
};
const STATUS_LABEL = {
  "consensus":             "CONSENSUS",
  "atlas-position":        "ATLAS POSITION",
  "contested":             "CONTESTED",
  "placeholder":           "PLACEHOLDER",
  "modeling-abstraction":  "MODELING ABSTRACTION",
};

// status: "consensus" = widely accepted; "atlas-position" = defensible but one of several options; "contested" = active debate
const PRIM_NODES = [
  { id: "distinction",  label: "Distinction",    symbol: "A ≠ B",       stream: "sym",
    status: "atlas-position",
    statusNote: "Spencer-Brown, structural realism, and information theory all treat distinction as primitive. Classical logic treats identity as primitive instead. Both stances are coherent; this atlas takes the distinction-first route.",
    tagline: "Symmetric difference. Irreducibly dyadic — one cannot exist without another.",
    body: `The most primitive structural fact for this atlas: two things are distinguishable. Symmetric — A≠B implies B≠A. No directionality.\n\nDistinction is treated as irreducibly dyadic here: a single thing differing from nothing is incoherent on this reading. The minimal unit of existence is the pair. For a thing to be distinct it presupposes at least one other thing to differ from. (Spencer-Brown's "Laws of Form" takes a single mark of distinction as primitive instead — a coherent alternative; this atlas adopts the relational reading.)\n\nAll information theory is built on this. Shannon entropy counts distinguishable states. The bit is a binary distinction. Identity (A=A) is treated here as the zero-distinction limit — derived, not primitive. A thing's identity IS its unique pattern of differences from everything else. (Classical first-order logic reverses this: identity is primitive, distinction defined as ¬identity. See the Identity node for the trade-off.)`,
    formula: "A ≠ B  [symmetric: A≠B ⟺ B≠A]\nH(X) = -Σ p(x) log₂ p(x)  [count of distinctions]\nBit ≡ minimal binary distinction {0,1}\nIdentity: A=A ⟺ d(A,A) = 0  [derived from Distinction, in this atlas]" },

  { id: "asymmetry",    label: "Asymmetry",      symbol: "A→B ≠ B→A",   stream: "asym",
    status: "atlas-position",
    statusNote: "The irreducibility argument is strong inductive evidence, not a formal proof. Causal set theory derives directed structure from a partial order axiom (taking asymmetry as primitive). Retrocausal QM proposals (Price, Wharton) and the two-state-vector formalism question whether fundamental physics has a primitive direction. The atlas commits to asymmetry as primitive; this is defensible but not forced.",
    tagline: "Directed difference. Second primitive — every known reduction either fails or smuggles direction back in.",
    body: `Asymmetry is taken here as a genuine second primitive, irreducible to symmetric distinction.\n\nThe argument: every attempted reduction of ordered pairs to unordered elements either fails or uses some form of directed structure in the encoding. Kuratowski's definition (A,B)={{A},{A,B}} relies on set membership (∈), which is asymmetric at the meta-level. From purely symmetric relations among the relata, only symmetric conclusions follow. To get direction, an asymmetric axiom must be introduced somewhere.\n\n⚠ This is a rhetorical / inductive argument, not a formal proof. Category theory defines ordered pairs via universal properties of products without an obviously "asymmetric" primitive — it uses mathematical structure, but that's a different question. The honest claim: no known reduction succeeds without smuggling, but absence of a counter-example is not impossibility.\n\nAsymmetry is what separates static topology from live causation. It generates time, process, and irreversibility — none derivable from symmetric difference in any extant framework the atlas takes seriously.`,
    formula: "A→B ≠ B→A  [antisymmetric]\nTE(X→Y) ≠ TE(Y→X)  [directed info flow]\nD_KL(P‖Q) ≠ D_KL(Q‖P)  [directed divergence]\nPartial order: reflexive + antisymmetric + transitive" },

  { id: "identity",     label: "Identity",       symbol: "d(A,A)=0",    stream: "sym",
    status: "atlas-position",
    statusNote: "Identity-as-derived is a structural-realist commitment. Substance metaphysics (Lowe, Wiggins) and classical first-order logic treat identity as primitive — sortalism requires identity-conditions prior to any pattern of differences. The atlas adopts the inversion; this is not logically forced.",
    tagline: "Zero distinction. Derived from Distinction as its limiting case — on the structural-realist reading.",
    body: `On the structural-realist / informational reading the atlas adopts: first there are distinctions, then things are individuated by their pattern of differences. Identity A=A is the case of zero distinction — derived, not primitive.\n\nThis inverts standard logic. Leibniz's Identity of Indiscernibles and Indiscernibility of Identicals treat identity as primitive; sortalism (Lowe, Wiggins) requires identity-conditions prior to any pattern of differences. The structural inversion is a metaphysical position aligned with Ladyman & Ross, not a discovery.\n\nWhy adopt it anyway: it makes structural realism work all the way down. Things don't pre-exist their relations; they are individuated by them. Information-theoretically clean: D_KL(P‖P) = 0 falls out naturally. Cost: gives up Leibniz-style primitive identity.`,
    formula: "A=A ⟺ d(A,A) = 0\nD_KL(P‖P) = 0  [self-KL vanishes at identity]\nEquivalence class: [A] = {x : d(x,A) = 0}" },

  { id: "information",  label: "Information",    symbol: "H=-Σp log p",  stream: "sym",
    status: "consensus",
    statusNote: "Shannon information is a settled mathematical framework. The metaphysical reading (information is fundamental / informational realism — see PCM framework) is contested; the operational use is not.",
    tagline: "Quantified distinction. Entropy counts distinguishable states — no directionality required.",
    body: `Shannon information is the expected bits to specify a state — average distinguishability of outcomes. A system with one distinguishable state has H=0: zero information, zero structure.\n\nInformation requires no directionality, no causation, no time. Mutual information I(X;Y)=I(Y;X) is symmetric — shared distinctions between variables with no implied direction.\n\nInformation theory is the formal science of counting distinctions. Its use as an operational tool is consensus. The further claim that information is metaphysically fundamental (Wheeler's "it from bit", Tegmark's Mathematical Universe, Wolfram, Lloyd) is a much stronger and contested position — see PCM in the Frameworks tab.`,
    formula: "H(X) = -Σ p(x) log₂ p(x)\nI(X;Y) = H(X) - H(X|Y) = I(Y;X)  [symmetric]\nSurprisal: i(x) = -log₂ p(x)" },

  { id: "ordering",     label: "Ordering",       symbol: "a < b < c",   stream: "asym",
    status: "consensus",
    statusNote: "Partial orders as the minimal structure derivable from asymmetry is mathematical fact. Whether physical time fundamentally is a partial order (causal set theory) vs. emergent from something deeper is contested in quantum gravity.",
    tagline: "Chain of directed relations. The proto-temporal structure — time itself may emerge from this.",
    body: `Ordering is the minimal structure from asymmetry alone: a partial order (reflexive, antisymmetric, transitive). From ordering emerge sequences, hierarchies, and the proto-temporal structure from which time may emerge.\n\nCausal set theory (Sorkin et al., quantum gravity) proposes that spacetime is fundamentally a partial order of events — time is not ontologically primitive but emerges from asymmetric relational ordering. If correct, process presupposes asymmetric structure, not the reverse. This is one approach among several in quantum gravity; alternatives (loop quantum gravity, string theory, causal dynamical triangulations) handle the order/geometry relationship differently.`,
    formula: "Partial order (P,≤):\n  a ≤ a              [reflexive]\n  a≤b ∧ b≤a → a=b   [antisymmetric]\n  a≤b ∧ b≤c → a≤c   [transitive]" },

  { id: "causation-p",  label: "Causation",      symbol: "do(A)→B",     stream: "asym",
    status: "contested",
    statusNote: "Pearl's interventionism is the dominant OPERATIONAL account but one of several metaphysical theories of causation. Atlas adopts the do-calculus marker; metaphysical commitment is left open.",
    tagline: "Asymmetric dependency. Interventionism is the operational marker — the underlying metaphysics is plural.",
    body: `Causation in this atlas is operationalized via Pearl's do-calculus: intervening on A changes B, but not vice versa. This directionality distinguishes causation from correlation — I(X;Y)=I(Y;X) is symmetric and cannot capture it.\n\n⚠ This is the dominant operational account, not the only metaphysical theory of causation. The serious alternatives in this atlas's own framework list:\n• Powers / dispositions (POW): causation = manifestation of powers; no intervention required\n• Mechanistic (MEC): causation = mechanism instantiation\n• Conserved-quantity (Salmon, Dowe): causation = transfer of conserved physical quantities\n• Counterfactual (Lewis): closest-world dependence\n• Process theories: causal lines carrying marks\n\nThe atlas uses interventionism because it is computable and operational. Whether this captures all that "causation" means metaphysically is open. Retrocausal proposals in QM foundations (Price, Wharton, two-state-vector formalism) further question whether causal direction is fundamental.`,
    formula: "P(B|do(A=a)) ≠ P(B)  [intervention asymmetry]\nCausal graph: A→B  [directed, not undirected]\nI(X;Y)=I(Y;X)  [symmetric — not causal]" },

  { id: "structure-p",  label: "Structure",      symbol: "G=(V,→E)",    stream: "both",
    status: "atlas-position",
    statusNote: "Treating structure and process as dual views of the same primitives is the structural-realist resolution. Orthodox process philosophy (Whitehead, Bergson, Dupré, Nicholson) denies the duality: process is more fundamental, networks are abstractions from process. The atlas takes the dual reading.",
    tagline: "Distinguishable nodes plus composable directed edges — built via Identity and Composition.",
    body: `Structure is what you get when distinguishable things are connected by composable directed relations. Its foundation in the derivation hierarchy:\n\n• Identity (from Distinction) — individuates the nodes V; without identity, no things to connect\n• Composition (from Asymmetry) — chains edges into paths; without composition, only isolated arrows, no network\n\nA directed graph G = (V, →E) requires both: distinguishable nodes plus chainable directed edges. The two primitives reach Structure through D1, not directly — Identity carries the distinction lineage, Composition carries the asymmetry lineage.\n\n⚠ The atlas's resolution of the process-vs-structure debate is a structural-realist position, not a settled finding. The dual reading (process and structure as synchronic/diachronic views of the same directed-relational fabric) presupposes the relational fabric is more fundamental than process. Orthodox process philosophy denies this: process is primary, "directed relational network" is itself an abstraction from process. This atlas adopts the dual reading because it makes structural realism and dynamical systems theory compatible. The deeper question — what is most fundamental? — is left open.`,
    formula: "Directed graph: G = (V, E⊆V×V)\nA_{ij} ≠ A_{ji}  [asymmetric adjacency]\nStructural info: Σ_v H(out-edges | v)" },

  { id: "process-p",    label: "Process",        symbol: "x(t₁)→x(t₂)", stream: "both",
    status: "atlas-position",
    statusNote: "On orthodox process ontology (Whitehead, Bergson, Dupré), process is more fundamental than structure. The atlas treats them as duals over a common primitive base — a structural-realist commitment, not a neutral starting point.",
    tagline: "Composed chain of causally driven temporal transitions — Ordering + Causation + Composition.",
    body: `Process is asymmetrically ordered evolution through distinguishable states. Three Derivation 1 ingredients feed it:\n\n• Ordering (from Asymmetry) — temporal sequence t₁ < t₂ < t₃\n• Causation (from Asymmetry) — drives state-to-state transitions\n• Composition (from Asymmetry) — chains transitions into trajectories x(t₁) → x(t₂) → x(t₃)\n\nA process is a composed chain of causally driven transitions through an ordered time. Notice all three feeders trace back to asymmetry — process is fundamentally a direction-saturated structure. Distinction enters via the distinguishable states being traversed (x(t₁) ≠ x(t₂)), but the active content comes from the asymmetry lineage.\n\nOn this atlas's reading, process does not supersede structural realism. A process presupposes the same primitives as structure, accessed through different D1 routes. "Human is a process" is true, but on the structural reading, process is not the foundational category — directed relational structure is.\n\n⚠ Orthodox process philosophy disagrees. Whitehead, Bergson, and modern process philosophers (Seibt, Dupré, Nicholson) hold that process is the primary ontological category, and "directed relational network" is itself an abstraction from process. The atlas's dual-view resolution is one option in this 2,500-year debate, not its conclusion.`,
    formula: "Trajectory: {x(t) : t ∈ (T,<)}\nFlow: φᵗ : X→X  [directed semigroup]\nProcess ≡ asymmetrically ordered sequence of distinctions" },

  { id: "irreversibility-p", label: "Irreversibility", symbol: "ΔS≥0",  stream: "both",
    status: "consensus",
    statusNote: "Thermodynamic irreversibility is observer-independent and empirically robust. The deeper question — whether the arrow of time is fundamental or emergent from time-symmetric laws + low-entropy boundary conditions (Past Hypothesis) — is contested in foundations of physics.",
    tagline: "Information + Causation — entropy increase as observer-independent physical asymmetry.",
    body: `Irreversibility is where asymmetry becomes physically concrete and observer-independent. Two Derivation 1 nodes feed it:\n\n• Information (from Distinction) — entropy ΔS ≥ 0 is informational. Landauer's bound gives the energetic cost of erasing a bit; entropy increase is a statement about distinguishable microstates becoming indistinguishable at the macro level.\n• Causation (from Asymmetry) — sets the arrow. Thermodynamic 'before/after' is causal asymmetry made physical.\n\nEntropy increase marks an asymmetric distinction between before and after — regardless of any observer. Stars burned and dissipated for 9 billion years before Earth existed. The thermodynamic arrow of time precedes and will outlast all cognitive structure.\n\nThis is the decisive anti-constructivist argument: the asymmetric structure of physical time is not imposed by minds. Structure doesn't wait for witnesses. Observers are themselves products of pre-observer structure.\n\n⚠ Note: this is consistent with the arrow being emergent from time-symmetric microscopic laws (Hamiltonian, Schrödinger) plus a low-entropy initial condition (the Past Hypothesis — Albert, Loewer, Wallace). "Observer-independent" and "fundamentally primitive" are different claims. The atlas's anti-constructivism rests on the former; the latter is a separate (open) question.`,
    formula: "dS/dt ≥ 0  [Second Law — observer-independent]\nLandauer: erasing 1 bit ≥ kT ln 2  joules\nD_KL(P_t ‖ P_{t+1}) > 0  [irreversible drift]" },

  { id: "emergence-p",  label: "Emergence",      symbol: "EI(M)>EI(μ)", stream: "emergent",
    status: "contested",
    statusNote: "Weak emergence (computational intractability) is consensus. Strong emergence (concepts absent at lower level + downward causation) is heavily disputed — Kim's exclusion argument is the standard objection. Hoel's causal emergence (EI marker) faces critiques from Dewhurst (2021), Eberhardt-Lee, and others on coarse-graining sensitivity.",
    tagline: "Novel distinctions at higher levels. Atlas takes a position; the field is divided.",
    body: `Emergence is when a higher level introduces distinctions — concepts, causal categories — with no analog at the lower level. Its derivation feeders span D1 and D2:\n\n• Structure, Process, Irreversibility — the D2 nodes whose interplay constitutes a macro level\n• Symmetry — symmetry-breaking is the canonical generator of emergent phenomena (phase transitions, gauge structure → particles, time-reversal breaking → arrow of time)\n• Information — Hoel's causal emergence is itself an information-theoretic measure (EI = H(do(X)) − H(X|do(X))). Emergence is detected via information theory, not separately from it.\n\nWeak: derivable in principle but computationally intractable from below. Consensus that this exists.\nStrong: the concepts simply don't exist at the lower level. "Wet" has no molecular analog. "Intention" has no single-neuron analog. Heavily contested.\n\n⚠ This atlas takes the position: strong emergence is real because irreversible thermodynamic dissipation during metastable formation creates genuinely novel macro-level distinctions, and Hoel's causal emergence (macro EI > micro EI) gives a measurable handle on this.\n\nThe critiques to know:\n• Kim's exclusion argument — if higher-level properties are causally efficacious AND lower-level dynamics are causally closed, you get systematic overdetermination. The atlas's escape route (irreversible info loss creates the macro level) is one move in a long argument, not settled.\n• Dewhurst (2021), Eberhardt-Lee — Hoel's EI depends on a uniform intervention prior; results sensitive to coarse-graining choice; the "objectively privileged macro" claim may not hold.\n• Dissipation ≠ emergence — heat-death isolated boxes dissipate without interesting emergence; reversible CAs show emergence without thermodynamic substrate.`,
    formula: "EI(M) = H(do(X_M)) - H(X_M|do(X_M))\nWeak: R:macro→micro exists but costly\nStrong: R:macro→micro does not exist\nInfo loss: H(micro|macro) > 0  [irreversibly]" },

  { id: "reflexivity-p", label: "Reflexivity",   symbol: "S⊃model(S)",  stream: "emergent",
    status: "contested",
    statusNote: "The deflationary verdict — \"no innate powers needed, reflexivity is derived\" — is a structural-realist position. Critical Realism (Bhaskar), Phenomenology (Husserl, Zahavi), and Powers metaphysics (Mumford, Bird) would each say reflexivity introduces irreducibly novel powers/properties. The hard problem of consciousness remains.",
    tagline: "Structure modeling its own structure. Atlas calls this derived; major traditions disagree.",
    body: `Reflexivity emerges when a directed-relational structure is complex enough to contain a sub-structure that models the whole.\n\nOn this atlas's reading: no extra ontological primitive required. Reflexivity is a derived property of sufficiently rich asymmetric networks. The reflexive organization creates novel feedback loops (the model influences the modeled) but no powers beyond physics.\n\n⚠ This is the structural-realist verdict and one position among several. The traditions that disagree:\n• Critical Realism (Bhaskar): each stratum has irreducible powers; reflexivity introduces new causal powers, not just rearrangements\n• Phenomenology (Husserl, Heidegger, Zahavi, Thompson): first-person experience is irreducibly novel; no third-person structural description captures it. Hard problem of consciousness stands.\n• Powers metaphysics (Mumford, Bird): properties are powers; reflexive systems have new powers their components lack.\n\nThe atlas adopts the deflationary verdict because it preserves naturalism without dualism. The cost: a substantive debate about whether something genuinely new appears with self-modeling, or whether sufficiently complex structure suffices.`,
    formula: "Strange loop: S ⊃ model(S)\nAutopoiesis: system produces its own organization\nKolmogorov: K(self-description) < K(external description)" },

  // ─── Derived (promoted from REJECTED list — shown as derivations rather than buried in prose) ──

  { id: "composition-p", label: "Composition", symbol: "(f∘g)∘h = f∘(g∘h)", stream: "asym",
    status: "atlas-position",
    statusNote: "Held in reserve. Category theory takes composition + associativity as foundational. The atlas treats it as a direct consequence of asymmetry — directed pairs can be chained. Could be upgraded to a third primitive if a categorial formalism is later adopted.",
    tagline: "Associativity of directed chaining. Derived from asymmetry alone; primitive in category theory.",
    body: `Once you have directed pairs (asymmetry), composition is the property that arrow-chains can be associated freely: (f∘g)∘h = f∘(g∘h). The chained traversal doesn't depend on which arrows you group first.\n\nThis sits at Derivation 1 because composition is fundamentally about chaining directed relations — symmetric distinction alone gives you no arrows to compose. Identity arrows are the degenerate case, not the foundation; the substantive content is the chaining of asymmetric relations.\n\nCategory theory makes this its foundation — objects + morphisms + composition + identity arrows + associativity. Topos theory, type theory, and Coecke-style diagrammatic compositional quantum mechanics all build from there. On those readings, composition is the irreducible operation that lets relations form a logical calculus.\n\nThe atlas inverts: composition is what asymmetric relations do, not what underlies them. Why: a category-theoretic foundation would force a heavier formalism than needed for the atlas's job. Composition is held in reserve as a candidate third primitive if a future formalism demands it.\n\nKey tension: if the atlas needs to express quantum-foundations or computational-mechanics structure end-to-end (where compositional structure is the natural language), composition may have to be promoted.`,
    formula: "f: A → B, g: B → C ⟹ g∘f: A → C\n(f∘g)∘h = f∘(g∘h)  [associativity]\nid_A: A → A  s.t. f∘id_A = f = id_B∘f" },

  { id: "symmetry-p",   label: "Symmetry",      symbol: "G ↷ X preserves",  stream: "both",
    status: "consensus",
    statusNote: "Standard mathematical structure built on distinctions plus invertible asymmetric operations. Symmetry-breaking — where a more-symmetric state becomes less symmetric through dynamics or boundary conditions — is the substantive physics content.",
    tagline: "Group action preserving structure. The only D2 node that reaches the primitives directly — no D1 mediator.",
    body: `A symmetry of a structure is an invertible transformation that preserves whatever relations or quantities define the structure. Formally: a group G acting on X such that for every g ∈ G, the action g·X preserves the structure of X. Constructible directly from distinction (what is preserved/changed) + asymmetry (the transformation direction).\n\nNote on the derivation hierarchy: Symmetry is the only Derivation 2 node with direct edges back to both primitives. All other D2 nodes (Structure, Process, Irreversibility) reach the primitives through Derivation 1 mediators. No D1 node naturally captures "preserving distinctions under directed transformation" — Identity is too weak (every transformation trivially preserves identity at some level); Composition is about chaining, not preservation. So Symmetry sits at D2 but talks to the primitives directly. This is a structural feature, not an inconsistency.\n\nWhy not promote to primitive? Symmetry is a property OF structures, not the structures themselves. Group theory presupposes elements already individuated by their pattern of distinctions; the group action then asks which distinctions a transformation preserves.\n\nThe substantive physics content is symmetry-breaking — phase transitions, gauge structure, the rich asymmetric world arising from more-symmetric underlying laws. Noether's theorem (continuous symmetry ↔ conserved quantity) is the deepest payoff and is the formal heart of L3 in the System Types tab.\n\nThis atlas treats symmetry as derived rather than primitive, but acknowledges that physics-first frameworks would weight it heavily.`,
    formula: "G × X → X  s.t. structure(g·x) = structure(x)\nNoether: continuous symmetry ⟺ conserved quantity\nSymmetry-breaking: ⟨φ⟩ ≠ 0 in vacuum  →  L4 phenomena" },

  { id: "self-other-p", label: "Self / Other",  symbol: "S ⊥ ¬S | b",   stream: "emergent",
    status: "atlas-position",
    statusNote: "Derived from emergence (boundary-supporting coarse-graining) + process (boundary maintenance over time). FEP treats Markov blankets as primitive systemhood; this atlas treats them as derived. Could be argued the other way — Self/Other as precondition for blanket individuation. See Active Inference and Enactivism subtabs in System Types.",
    tagline: "Boundary-marked separation of system from environment. Derived; primitive in FEP / Enactivism.",
    body: `Self/Other is the distinction a system draws between itself and its environment. Formally: the existence of a Markov blanket b = {sensory, active states} such that internal states and external states are conditionally independent given the blanket — S ⊥ ¬S | b. The blanket is what makes "internal" and "external" well-defined.\n\nDerived: requires emergence (the system-level coarse-graining that supports the boundary) and process (the boundary must be maintained against perturbation, not just exist statically). Enactivism makes operational closure primitive; FEP makes blanket-maintenance primitive. This atlas treats it as falling out of more basic structure — and notes that the inversion (Self/Other as precondition) is a coherent alternative.\n\nThe deeper question: can you have Self/Other without explicit self-modeling? Bacterial chemotaxis arguably has the former without the latter — a minimal boundary maintained without representational content. The atlas's stance: minimally-reflexive boundary maintenance suffices for Self/Other; full self-modeling is Reflexivity. The distinction matters when classifying which entities count as systems with a "self."`,
    formula: "Markov blanket b = {s, a}\nS ⊥ ¬S | b  [conditional independence]\nMaintained: ∂_t p(s, a, S, ¬S) ≈ 0  [stationary]" },

  // ─── External — open questions and rival primitives shown outside the derivation hierarchy ──

  { id: "continuity-x", label: "Continuity ⇄ Discreteness", symbol: "ℝ vs ℤ vs ?", stream: "emergent",
    external: true, externalKind: "open",
    status: "placeholder",
    statusNote: "Genuinely open and the atlas takes no stance. Whether reality is fundamentally continuous (smooth manifolds), discrete (causal sets, lattice, digital physics), or something else (Wolfram-style hypergraphs, 't Hooft cellular automata) is a substrate choice — both are compatible with the primitives.",
    tagline: "Substrate-level fork; the atlas's primitives work either way.",
    body: `Whether the world is continuous (manifolds, ODEs, gauge fields with smooth Lie groups) or discrete (causal sets, lattice models, digital physics, cellular automata, Wolfram hypergraphs) is a foundational physics fork the atlas does not adjudicate.\n\nBoth are compatible with distinction + asymmetry as primitives:\n• Continuous: distinctions are real-valued, asymmetry is direction in tangent space, information uses differential entropy.\n• Discrete: distinctions are between cells, asymmetry is partial order on cells, information uses Shannon entropy.\n\nThis matters substantially for: quantum gravity programs (causal sets vs string theory vs loop quantum gravity), simulability claims (digital physics, Wolfram's Physics Project), the status of singularities, and the meta-question of whether physical reality is computable ('t Hooft's deterministic interpretation, Lloyd's universe-as-computer).\n\nNeither continuity nor discreteness is forced by the primitives. The choice is empirical/foundational, not derivable.`,
    formula: "Continuous: x ∈ ℝⁿ, dynamics = ODEs\nDiscrete: x ∈ ℤⁿ or finite, dynamics = updates\nBoth: information theory + structural realism apply" },

  { id: "probability-x", label: "Probability", symbol: "P, Born rule", stream: "emergent",
    external: true, externalKind: "open",
    status: "placeholder",
    statusNote: "Genuinely open and the atlas takes no stance. Classical probability reduces to measure on a distinction-structured event space. Quantum probability (Born rule) has derivations from Hilbert space structure (Gleason 1957, Deutsch-Wallace decision-theoretic, Zurek envariance) — but all are contested. The atlas uses probability operationally without committing.",
    tagline: "Whether quantum probability reduces to the two primitives is open.",
    body: `Classical probability (frequentist or Bayesian) reduces straightforwardly to distinction + asymmetry: it's a measure on a distinction-structured event space, with asymmetric conditioning P(A|B) ≠ P(B|A). No new primitive is needed.\n\nQuantum probability via the Born rule is different. Derivations exist:\n• Gleason's theorem (1957) — any probability assignment on a Hilbert space respecting certain constraints must obey the Born rule\n• Deutsch-Wallace decision-theoretic — rational agents in Everettian QM should weight branches by amplitude squared\n• Zurek's envariance — Born rule from symmetry under entangled-environment swaps\n\nAll three are contested. Whether quantum stochasticity is reducible to the two primitives or genuinely novel remains open. The atlas uses probability operationally (entropy, MI, KL) without committing to whether stochasticity is primitive or emergent from deterministic substrate + ignorance.`,
    formula: "Classical: P: F → [0,1] on σ-algebra over distinctions\nBorn rule: P(outcome|state) = |⟨φ|ψ⟩|²\nReduction to D + A: genuinely open" },

  { id: "locality-x",   label: "Locality / Space",  symbol: "[O(x), O(y)] = 0",  stream: "emergent",
    external: true, externalKind: "open",
    status: "placeholder",
    statusNote: "Genuinely open and the atlas takes no stance. Bell's theorem rules out local hidden variables. Holographic principle (AdS/CFT, Maldacena 1997), entanglement-from-geometry programs (Van Raamsdonk 2010, ER=EPR), and broader spacetime-as-emergent proposals (Verlinde) suggest locality may be derived from more primitive entanglement structure — but the question remains open.",
    tagline: "Whether space and locality are primitive or emergent is open.",
    body: `The atlas's primitives are silent on whether relations have intrinsic spatial structure. In current physics:\n• Classical fields are local; quantum fields commute at spacelike separation\n• Quantum states violate Bell inequalities — no local hidden variables (Aspect 1982, Hensen 2015)\n• Holographic principle (AdS/CFT) reconstructs bulk spacetime from boundary entanglement structure\n• Van Raamsdonk and ER=EPR (Maldacena-Susskind): entanglement IS spatial connectivity\n• Verlinde-style emergent gravity: spacetime as thermodynamic phenomenon\n\nIf spacetime emerges from entanglement, locality is derived, not primitive. If spacetime is fundamental, locality has its own ontological status not captured by distinction + asymmetry. Neither stance is forced by the primitives — the atlas's relations could in principle be spatially extended or not.\n\nThis is one of the deepest open foundational questions in physics; the atlas's primitives are compatible with several outcomes.`,
    formula: "Bell: |⟨AB⟩+⟨AB'⟩+⟨A'B⟩−⟨A'B'⟩| ≤ 2  (classical)\nQM: 2√2  (violated experimentally)\nAdS/CFT: bulk geometry ↔ boundary entanglement" },

  { id: "modality-x",   label: "Modality (CT)", symbol: "□T, ◊T",  stream: "emergent",
    external: true, externalKind: "rival-primitive",
    status: "contested",
    statusNote: "Rival primitive — Constructor Theory (Deutsch 2013, Marletto, Vedral) takes counterfactual task-possibility as foundational. Laws of physics become laws of impossibility. This atlas operationalizes modality via Pearl's do-calculus (intervention asymmetry) but does not treat possibility as primitive. See Constructor subtab in System Types.",
    tagline: "Constructor Theory's primitive. Atlas derives modality from do-calculus asymmetry.",
    body: `Constructor Theory (Deutsch 2013, Marletto-Vedral) makes counterfactual possibility primitive. Laws of physics, on CT's reading, are laws of impossibility: "no constructor can perform task T" is the deepest law form. Existence, information, and knowledge are downstream of which transformations are physically possible.\n\nThe atlas instead uses Pearl's do-calculus, in which modality is operationalized as the asymmetry between observation and intervention: P(Y|do(X=x)) ≠ P(Y|X=x). Counterfactuals are derived from causal asymmetry, not primitive.\n\nThe deepest disagreement: which is more fundamental, what IS or what CAN BE? The atlas says: what IS (states + dynamics, built from D + A) is primitive; what CAN BE follows. Constructor Theory inverts: what CAN BE is primitive; what IS happens to be one realization among the possible.\n\nThis is the cleanest example in the atlas of a rival primitive — not "open" (which means we don't know) but "rejected" (which means we know what we'd need to give up to adopt it). See the Constructor subtab in System Types for the full alternative.`,
    formula: "Pearl: P(Y|do(X=x)) ≠ P(Y|X=x)   [intervention ≠ observation]\nCT: T is possible ⟺ ∃ constructor C performing T reliably\nAtlas: modality derived from causal asymmetry" },
];

// Concepts considered as primitives and rejected, or held in reserve. Honesty about what's excluded matters.
// The `shownInDiagram` flag indicates which entries are also rendered as nodes in the diagram —
// derivations for the three that the atlas treats as derived; external nodes for the four open/rival items.
const REJECTED_PRIMITIVES = [
  { name: "Composition / Associativity", verdict: "Held in reserve · now shown as derivation",
    shownInDiagram: "derivation",
    reason: "Category theory takes composition as foundational. The atlas treats it as a property of derived structure (directed graphs compose; processes compose; functors preserve composition). Plausibly upgradeable to a third primitive if a categorial formalism is later adopted. Shown as a Derivation-2 node in the diagram." },
  { name: "Symmetry / Symmetry-breaking", verdict: "Derived · now shown as derivation",
    shownInDiagram: "derivation",
    reason: "Crucial for physics but not foundational here. Symmetry is a property OF structures (invertible transformations that preserve them), not the structures themselves. Symmetry-breaking is the substantive physics content — explaining how the rich asymmetric world arises from more-symmetric microphysics. Shown as a Derivation-2 node in the diagram." },
  { name: "Self / Other", verdict: "Derived · now shown as derivation",
    shownInDiagram: "derivation",
    reason: "Plausibly more primitive than Reflexivity, but the atlas treats it as derived from boundary structure (emergence) + sufficient internal process (boundary maintenance). FEP and Enactivism treat this as primitive instead — see the Active Inference and Enactivism subtabs in System Types. Shown as a Derivation-3 node in the diagram." },
  { name: "Continuity vs Discreteness", verdict: "Genuinely open · shown as external",
    shownInDiagram: "external",
    reason: "Whether reality is fundamentally continuous (smooth manifolds, ODEs) or discrete (lattice, causal sets, digital physics) is a foundational fork the atlas does not adjudicate. Both are compatible with the primitives. Shown in the OUTSIDE DERIVATION band with the open-question indicator (?)." },
  { name: "Probability / Indeterminism", verdict: "Genuinely open · shown as external",
    shownInDiagram: "external",
    reason: "Quantum probabilities (Born rule) may not reduce to distinction + asymmetry. Derivations exist (Gleason, Deutsch-Wallace, Zurek) but all are contested. The atlas uses probability operationally (entropy, MI) without committing to whether stochasticity is primitive or emergent. Shown in the OUTSIDE DERIVATION band with the open-question indicator (?)." },
  { name: "Locality / Spatial extension", verdict: "Genuinely open · shown as external",
    shownInDiagram: "external",
    reason: "Bell's theorem rules out local hidden variables in QM. Whether spatial structure is fundamental or emergent (holographic principle, entanglement-from-geometry, ER=EPR) is a live question. The atlas's primitives are silent on whether relations have intrinsic spatial structure. Shown in the OUTSIDE DERIVATION band with the open-question indicator (?)." },
  { name: "Possibility / Modality", verdict: "Rival primitive (Constructor Theory) · shown as external",
    shownInDiagram: "external",
    reason: "Constructor Theory (Deutsch & Marletto) takes counterfactual task-possibility as primitive. The atlas uses modality operationally (do-calculus is modal) but does not treat possibility as a fundamental category — this is a CT-vs-atlas disagreement, see the Constructor subtab in System Types. Shown in the OUTSIDE DERIVATION band with the rival-primitive indicator (↗) in CT's color." },
];

// Layout for SVG_W = 820, SVG_H = 502 (4 rows of derivation + 1 row external)
// PRIMITIVES (y=24)  →  DERIVATION 1 (y=128)  →  DERIVATION 2 (y=232)  →  DERIVATION 3 (y=336)
// OUTSIDE DERIVATION (y=440): open questions + rival primitives — no edges, dashed borders
const PRIM_POS = {
  // Primitives (2 nodes, centered)
  distinction:        { x: 240, y: 24 },
  asymmetry:          { x: 460, y: 24 },
  // Derivation 1 — direct (5 nodes: identity, information, composition, ordering, causation)
  identity:           { x: 20,  y: 128 },
  information:        { x: 170, y: 128 },
  "composition-p":    { x: 320, y: 128 },
  ordering:           { x: 480, y: 128 },
  "causation-p":      { x: 640, y: 128 },
  // Derivation 2 — requires both (4 nodes: structure, symmetry, process, irreversibility)
  "structure-p":      { x: 68,  y: 232 },
  "symmetry-p":       { x: 256, y: 232 },
  "process-p":        { x: 444, y: 232 },
  "irreversibility-p":{ x: 632, y: 232 },
  // Derivation 3 — emergent (3 nodes: emergence, self-other, reflexivity)
  "emergence-p":      { x: 115, y: 336 },
  "self-other-p":     { x: 350, y: 336 },
  "reflexivity-p":    { x: 585, y: 336 },
  // Outside derivation — open & rival primitives (4 nodes, no edges)
  "continuity-x":     { x: 68,  y: 440 },
  "probability-x":    { x: 256, y: 440 },
  "locality-x":       { x: 444, y: 440 },
  "modality-x":       { x: 632, y: 440 },
};
const PNW = 120, PNH = 42;

const PRIM_EDGES = [
  // ─── Primitives → Derivation 1 (direct derivations) ─────────────────────
  { from: "distinction", to: "identity" },
  { from: "distinction", to: "information" },
  { from: "asymmetry",   to: "composition-p" },
  { from: "asymmetry",   to: "ordering" },
  { from: "asymmetry",   to: "causation-p" },

  // ─── Derivation 1 → Derivation 2 (D1 nodes mediate primitives' role in D2) ─
  { from: "identity",      to: "structure-p" },          // individuates V in G=(V,→E)
  { from: "composition-p", to: "structure-p" },          // chains edges into paths
  { from: "ordering",      to: "process-p" },            // temporal sequence t₁<t₂<…
  { from: "causation-p",   to: "process-p" },            // causation drives state-transitions
  { from: "composition-p", to: "process-p" },            // transitions chain into trajectories
  { from: "information",   to: "irreversibility-p" },    // ΔS ≥ 0 is informational (Landauer, entropy)
  { from: "causation-p",   to: "irreversibility-p" },    // causal asymmetry sets the arrow

  // ─── Primitives → Derivation 2 (only where no D1 mediator applies) ──────
  { from: "distinction", to: "symmetry-p" },             // group action preserves distinctions
  { from: "asymmetry",   to: "symmetry-p" },             // ...under directed transformations

  // ─── Derivation 2 → Derivation 3 (emergent properties) ──────────────────
  { from: "structure-p",      to: "emergence-p" },
  { from: "symmetry-p",       to: "emergence-p" },       // symmetry-breaking → emergent phenomena
  { from: "process-p",        to: "emergence-p" },
  { from: "irreversibility-p",to: "emergence-p" },
  { from: "information",      to: "emergence-p" },       // Hoel's EI is an info-theoretic measure of emergence

  { from: "emergence-p",      to: "self-other-p" },
  { from: "process-p",        to: "self-other-p" },
  { from: "irreversibility-p",to: "self-other-p" },      // Markov blanket maintained by irreversible dissipation

  { from: "structure-p",      to: "reflexivity-p" },
  { from: "process-p",        to: "reflexivity-p" },
  { from: "emergence-p",      to: "reflexivity-p" },
  { from: "self-other-p",     to: "reflexivity-p" },     // atlas commitment: Self/Other is precondition for Reflexivity
];

function PrimitivesTab() {
  const [sel, setSel] = useState("distinction");
  const [showCommit, setShowCommit] = useState(false);
  const [showRejected, setShowRejected] = useState(false);
  const node = PRIM_NODES.find(n => n.id === sel);
  const SVG_W = 820, SVG_H = 440 + PNH + 25;

  return (
    <div style={{ padding: "20px 24px 60px", maxWidth: 920, margin: "0 auto" }}>
      <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 8, padding: "14px 18px", marginBottom: 14 }}>
        <div style={{ fontSize: 15, fontWeight: 600, color: C.text, marginBottom: 6 }}>
          Ontological Primitives — the minimal foundation
        </div>
        <div style={{ fontSize: 12.5, color: C.textDim, lineHeight: 1.65 }}>
          Two primitives proposed as the minimal foundation of this atlas:{" "}
          <span style={{ color: P_SYM, fontWeight: 600 }}>Distinction</span> (symmetric difference) and{" "}
          <span style={{ color: P_ASYM, fontWeight: 600 }}>Asymmetry</span> (directed difference). The claim that neither
          reduces to the other is strong inductive evidence (every known attempt smuggles direction back in),
          not a formal proof. The derivation hierarchy below builds everything from one or both. Click a node for the argument and its status.
        </div>
        <div style={{ fontSize: 11.5, color: C.muted, marginTop: 8, lineHeight: 1.55, fontStyle: "italic" }}>
          This is the <span style={{ color: C.text, fontStyle: "normal", fontWeight: 600 }}>derivation hierarchy</span> — what can be constructed from the primitives. The bottom band <span style={{ color: C.text, fontStyle: "normal", fontWeight: 600 }}>OUTSIDE DERIVATION</span> shows items considered as primitives and not adopted: open questions where the atlas takes no stance (<span style={{ fontFamily: "ui-monospace,monospace" }}>?</span>) and rival primitives from other frameworks (<span style={{ fontFamily: "ui-monospace,monospace", color: C.con }}>↗</span>). Those nodes have dashed borders and no connecting edges — they are shown for context, not derived. For <span style={{ color: C.text, fontStyle: "normal", fontWeight: 600 }}>kinds of systems</span> built with these constructions, see the <span style={{ color: C.sr, fontStyle: "normal", fontWeight: 600 }}>System Types</span> tab. Note: "Derivation N" here ≠ "L-N" in System Types.
        </div>
        <div style={{ display: "flex", gap: 16, marginTop: 10, flexWrap: "wrap", alignItems: "center" }}>
          {Object.entries(PSTREAM_LABEL).map(([k, l]) => (
            <div key={k} style={{ display: "flex", alignItems: "center", gap: 5 }}>
              <div style={{ width: 9, height: 9, borderRadius: 2, background: PSTREAM_COLOR[k] }} />
              <span style={{ fontSize: 11, color: C.muted, fontFamily: "ui-monospace, monospace" }}>{l}</span>
            </div>
          ))}
          <div style={{ width: 1, height: 12, background: C.border }} />
          {Object.entries(STATUS_LABEL).map(([k, l]) => (
            <div key={k} style={{ display: "flex", alignItems: "center", gap: 5 }}>
              <div style={{ width: 9, height: 9, borderRadius: 2, background: STATUS_COLOR[k] }} />
              <span style={{ fontSize: 11, color: C.muted, fontFamily: "ui-monospace, monospace" }}>{l}</span>
            </div>
          ))}
        </div>
      </div>

      {/* ATLAS COMMITMENTS — explicit listing of the metaphysical-formal package */}
      <div style={{ background: C.surface, border: "1px solid #fbbf2455", borderLeft: "3px solid #fbbf24", borderRadius: 6, marginBottom: 14 }}>
        <div onClick={() => setShowCommit(v => !v)} style={{ cursor: "pointer", padding: "10px 14px", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <div>
            <span style={{ fontSize: 9.5, color: "#fbbf24", background: "#fbbf2418", border: "1px solid #fbbf2444", padding: "1px 7px", borderRadius: 3, letterSpacing: 0.5, fontFamily: "ui-monospace,monospace", fontWeight: 700 }}>ATLAS COMMITMENTS</span>
            <span style={{ fontSize: 13, color: C.text, fontWeight: 600, marginLeft: 10 }}>The metaphysical-formal package this atlas adopts</span>
          </div>
          <span style={{ fontSize: 14, color: C.muted }}>{showCommit ? "−" : "+"}</span>
        </div>
        {showCommit && (
          <div style={{ padding: "0 14px 14px", borderTop: `1px solid ${C.border}` }}>
            <div style={{ fontSize: 12, color: C.textDim, lineHeight: 1.65, marginTop: 10, marginBottom: 10 }}>
              Many nodes in this atlas assert positions in active debates. Rather than smuggle these in silently, the package is listed here:
            </div>
            <div style={{ display: "flex", flexDirection: "column", gap: 7 }}>
              {[
                { label: "Ontic Structural Realism", who: "Ladyman & Ross 2007", role: "Relations are primary; objects are nodes in relational structure. Identity is derived from pattern of difference. Rivals: substance metaphysics, standard scientific realism." },
                { label: "Information Theory as quantitative anchor", who: "Shannon and successors", role: "Distinctions are counted and weighted by entropy / MI / KL / TE. Operational; framework-neutral. Stronger version (informational realism, PCM) NOT adopted — see Frameworks tab." },
                { label: "Interventionism for causation", who: "Pearl, Spirtes-Glymour-Scheines", role: "Causation operationalized as do-calculus asymmetry. Metaphysical alternatives (powers, conserved-quantity, counterfactual) acknowledged but not embedded in the primitives." },
                { label: "Hoel causal emergence for strong emergence", who: "Hoel, Albantakis, Tononi 2013", role: "Macro-EI > micro-EI as the measurable marker. ⚠ Contested — Dewhurst, Eberhardt-Lee critique. Atlas takes the position; consensus has not." },
                { label: "Process and Structure as duals", who: "Atlas-specific synthesis", role: "Resolution of the Whitehead/Aristotle debate via the two primitives. Orthodox process philosophy (Dupré, Nicholson, Seibt) disagrees: process is fundamental." },
                { label: "Deflationary reflexivity", who: "Atlas-specific", role: "Self-modeling is a derived property of sufficiently rich asymmetric networks — no \"innate powers\" beyond physics. Critical Realism, Phenomenology, and Powers metaphysics each disagree." },
                { label: "Past Hypothesis–compatible anti-constructivism", who: "Albert, Loewer, Wallace", role: "The arrow of time is observer-independent. Whether it is fundamental or emergent from time-symmetric laws + low-entropy initial conditions is open — but in either case it does not depend on observers." },
                { label: "Friston/active inference as one option at L5–L7", who: "Friston 2006+", role: "Variational free energy used as the L5 info quantity. Other choices (expected utility, fitness, control-theoretic cost) noted in INFO_AXIS commentary." },
              ].map((c, i) => (
                <div key={i} style={{ background: C.surface2, borderLeft: "2px solid #fbbf24aa", padding: "8px 10px", borderRadius: 4 }}>
                  <div style={{ display: "flex", justifyContent: "space-between", gap: 8, flexWrap: "wrap", marginBottom: 3 }}>
                    <span style={{ fontSize: 12, fontWeight: 600, color: C.text }}>{c.label}</span>
                    <span style={{ fontSize: 10, color: C.muted, fontFamily: "ui-monospace,monospace" }}>{c.who}</span>
                  </div>
                  <div style={{ fontSize: 11.5, color: C.textDim, lineHeight: 1.55 }}>{c.role}</div>
                </div>
              ))}
            </div>
            <div style={{ fontSize: 11, color: C.muted, marginTop: 10, lineHeight: 1.5, fontStyle: "italic" }}>
              These commitments are coherent as a package and defensible. They are not the only coherent package, and the atlas tries to mark where each commitment is doing work.
            </div>
          </div>
        )}
      </div>

      <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 8, padding: 8, overflowX: "auto", marginBottom: 14 }}>
        <svg viewBox={`0 0 ${SVG_W} ${SVG_H}`} style={{ minWidth: 620, width: "100%", height: "auto", display: "block" }}>
          {/* Arrowhead markers — one per stream color. markerUnits="userSpaceOnUse" locks size to pixels (not stroke-relative). */}
          <defs>
            {[
              { id: "prim-arr-sym",  color: P_SYM },
              { id: "prim-arr-asym", color: P_ASYM },
              { id: "prim-arr-both", color: P_BOTH },
              { id: "prim-arr-em",   color: P_EMRG },
            ].map(m => (
              <marker key={m.id} id={m.id} viewBox="0 0 10 10" refX="10" refY="5"
                markerWidth="7" markerHeight="7"
                markerUnits="userSpaceOnUse"
                orient="auto-start-reverse">
                <path d="M 0 0 L 10 5 L 0 10 z" fill={m.color} />
              </marker>
            ))}
          </defs>

          {/* Row labels */}
          {[
            { y: 14,  txt: "PRIMITIVES" },
            { y: 118, txt: "DERIVATION 1 — direct derivations" },
            { y: 222, txt: "DERIVATION 2 — requires both" },
            { y: 326, txt: "DERIVATION 3 — emergent" },
            { y: 430, txt: "OUTSIDE DERIVATION — open questions & rival primitives" },
          ].map((l, i) => (
            <text key={i} x={SVG_W - 8} y={l.y} textAnchor="end" fill={C.muted} fontSize={9} fontWeight={700} letterSpacing={0.7} fontFamily="ui-monospace,monospace">{l.txt}</text>
          ))}
          {/* Separator above external row */}
          <line x1={20} y1={405} x2={SVG_W - 20} y2={405}
            stroke={C.muted} strokeWidth={0.7} strokeOpacity={0.3} strokeDasharray="2,4" />
          <text x={20} y={400} fill={C.muted} fontSize={8.5} fontStyle="italic" opacity={0.65}>
            below: not derived from the primitives — shown for context
          </text>

          {/* Edges — sort so active edges render LAST. Endpoints anchored to rectangle borders by direction. */}
          {[...PRIM_EDGES]
            .filter(e => {
              const tn = PRIM_NODES.find(n => n.id === e.to);
              return !(tn && tn.external);
            })
            .sort((a, b) => {
              const aActive = (sel === a.from || sel === a.to) ? 1 : 0;
              const bActive = (sel === b.from || sel === b.to) ? 1 : 0;
              return aActive - bActive;
            })
            .map(e => {
              const fn = PRIM_NODES.find(n => n.id === e.from);
              const fp = PRIM_POS[e.from], tp = PRIM_POS[e.to];
              const isActive = sel === e.from || sel === e.to;

              // Centers
              const scx = fp.x + PNW / 2, scy = fp.y + PNH / 2;
              const tcx = tp.x + PNW / 2, tcy = tp.y + PNH / 2;
              const dx = tcx - scx, dy = tcy - scy;
              const len = Math.sqrt(dx * dx + dy * dy) || 1;

              // Compute where a ray from center (cx, cy) in direction (vx, vy) exits a rectangle of (PNW × PNH)
              const exitPoint = (cx, cy, vx, vy) => {
                if (vx === 0 && vy === 0) return [cx, cy];
                const hw = PNW / 2, hh = PNH / 2;
                let t = Infinity;
                if (vx > 0) t = Math.min(t, hw / vx);
                else if (vx < 0) t = Math.min(t, -hw / vx);
                if (vy > 0) t = Math.min(t, hh / vy);
                else if (vy < 0) t = Math.min(t, -hh / vy);
                return [cx + vx * t, cy + vy * t];
              };

              const [x1, y1] = exitPoint(scx, scy, dx, dy);
              const [x2Raw, y2Raw] = exitPoint(tcx, tcy, -dx, -dy);

              // Small pullback so arrowhead tip sits just outside target border (active only)
              const pullback = isActive ? 3 : 0;
              const x2 = x2Raw - (dx / len) * pullback;
              const y2 = y2Raw - (dy / len) * pullback;

              const markerId = isActive ? ({
                sym: "prim-arr-sym",
                asym: "prim-arr-asym",
                both: "prim-arr-both",
                emergent: "prim-arr-em",
              }[fn.stream]) : null;

              return (
                <line key={`${e.from}->${e.to}`}
                  x1={x1} y1={y1}
                  x2={x2} y2={y2}
                  stroke={PSTREAM_COLOR[fn.stream]}
                  strokeWidth={isActive ? 2.2 : 0.7}
                  strokeOpacity={isActive ? 0.9 : 0.13}
                  strokeDasharray={isActive ? "none" : "4,3"}
                  strokeLinecap="round"
                  markerEnd={markerId ? `url(#${markerId})` : undefined} />
              );
            })}

          {/* Nodes */}
          {PRIM_NODES.map(n => {
            const p = PRIM_POS[n.id], isActive = n.id === sel;
            const isExternal = n.external;
            // For "rival-primitive" external, use Constructor Theory's color to link the visual claim;
            // other externals use a muted/grey treatment.
            const baseCol = isExternal
              ? (n.externalKind === "rival-primitive" ? C.con : C.muted)
              : PSTREAM_COLOR[n.stream];
            const statusCol = STATUS_COLOR[n.status];
            // External icon depending on kind
            const extIcon = isExternal
              ? (n.externalKind === "rival-primitive" ? "↗" : "?")
              : null;
            const nodeOpacity = isExternal && !isActive ? 0.7 : 1;
            return (
              <g key={n.id} onClick={() => setSel(n.id)} style={{ cursor: "pointer" }} opacity={nodeOpacity}>
                <rect x={p.x} y={p.y} width={PNW} height={PNH} rx={6}
                  fill={isActive ? `${baseCol}1c` : C.surface2}
                  stroke={isActive ? baseCol : `${baseCol}${isExternal ? "66" : "44"}`}
                  strokeWidth={isActive ? 1.8 : 1}
                  strokeDasharray={isExternal ? "5,3" : undefined} />
                <text x={p.x + PNW / 2} y={p.y + 15} textAnchor="middle"
                  fill={isActive ? baseCol : C.text}
                  fontSize={11} fontWeight={700}
                  fontFamily="'IBM Plex Sans',system-ui,sans-serif"
                  fontStyle={isExternal ? "italic" : "normal"}>{n.label}</text>
                <text x={p.x + PNW / 2} y={p.y + 30} textAnchor="middle"
                  fill={isActive ? baseCol : C.muted}
                  fontSize={9.5} fontFamily="ui-monospace,'IBM Plex Mono',monospace">{n.symbol}</text>
                {/* External-kind icon — top-left corner */}
                {extIcon && (
                  <text x={p.x + 7} y={p.y + 11} fill={baseCol} fontSize={10}
                    fontWeight={700} fontFamily="ui-monospace,monospace">
                    {extIcon}
                    <title>
                      {n.externalKind === "rival-primitive" ? "Rival primitive (other framework takes this as foundational)" : "Genuinely open — atlas takes no stance"}
                    </title>
                  </text>
                )}
                {/* Status dot in top-right corner */}
                {statusCol && (
                  <circle cx={p.x + PNW - 6} cy={p.y + 6} r={3} fill={statusCol} stroke={C.surface} strokeWidth={0.8}>
                    <title>{STATUS_LABEL[n.status]}</title>
                  </circle>
                )}
              </g>
            );
          })}
        </svg>
      </div>

      <div style={{ fontSize: 10.5, color: C.muted, fontStyle: "italic", textAlign: "center", marginTop: -8, marginBottom: 14, lineHeight: 1.5 }}>
        Arrows point from <span style={{ color: C.text, fontStyle: "normal", fontWeight: 600 }}>feeder</span> to <span style={{ color: C.text, fontStyle: "normal", fontWeight: 600 }}>dependent</span> — <code style={{ fontFamily: "ui-monospace,monospace", color: C.text, fontStyle: "normal" }}>X → Y</code> means Y is built from X. Direction shown only on active (clicked) edges to keep inactive context readable.
      </div>

      {node && (() => {
        const isExt = node.external;
        const detailCol = isExt && node.externalKind === "rival-primitive" ? C.con
                        : isExt ? C.muted
                        : PSTREAM_COLOR[node.stream];
        const detailLabel = isExt
          ? (node.externalKind === "rival-primitive" ? "OUTSIDE DERIVATION · RIVAL PRIMITIVE" : "OUTSIDE DERIVATION · OPEN")
          : PSTREAM_LABEL[node.stream];
        return (
        <div style={{ background: C.surface, border: `1px solid ${detailCol}44`, borderLeft: `3px solid ${detailCol}`, borderRadius: 6, overflow: "hidden", marginBottom: 14 }}>
          <div style={{ padding: "11px 16px", borderBottom: `1px solid ${C.border}`, display: "flex", alignItems: "center", gap: 10, flexWrap: "wrap" }}>
            <div style={{ fontSize: 9.5, color: detailCol, background: `${detailCol}14`, border: `1px solid ${detailCol}33`, padding: "1px 7px", borderRadius: 3, letterSpacing: 0.5, fontFamily: "ui-monospace,monospace", fontWeight: 700, textTransform: "uppercase" }}>
              {detailLabel}
            </div>
            {node.status && (
              <div style={{ fontSize: 9.5, color: STATUS_COLOR[node.status], background: `${STATUS_COLOR[node.status]}14`, border: `1px solid ${STATUS_COLOR[node.status]}44`, padding: "1px 7px", borderRadius: 3, letterSpacing: 0.5, fontFamily: "ui-monospace,monospace", fontWeight: 700 }}>
                {STATUS_LABEL[node.status]}
              </div>
            )}
            <div style={{ fontSize: 15, fontWeight: 600, color: C.text }}>{node.label}</div>
            <code style={{ fontSize: 11, color: C.muted, fontFamily: "ui-monospace,'IBM Plex Mono',monospace" }}>{node.symbol}</code>
          </div>
          {node.statusNote && (
            <div style={{ padding: "8px 16px", background: `${STATUS_COLOR[node.status]}08`, borderBottom: `1px solid ${C.border}`, fontSize: 11.5, color: STATUS_COLOR[node.status], lineHeight: 1.55 }}>
              <strong style={{ color: STATUS_COLOR[node.status] }}>{STATUS_LABEL[node.status]} — </strong>
              <span style={{ color: C.textDim }}>{node.statusNote}</span>
            </div>
          )}
          <div style={{ padding: "12px 16px", background: `${detailCol}07` }}>
            <div style={{ fontSize: 12.5, color: detailCol, fontStyle: "italic", marginBottom: 8, lineHeight: 1.5 }}>{node.tagline}</div>
            <div style={{ fontSize: 13, color: C.text, lineHeight: 1.72, whiteSpace: "pre-line" }}>{node.body}</div>
          </div>
          <pre style={{ margin: 0, padding: "10px 16px", background: C.surface2, borderTop: `1px solid ${C.border}`, fontSize: 11, lineHeight: 1.6, color: detailCol, fontFamily: "ui-monospace,'IBM Plex Mono',monospace", whiteSpace: "pre-wrap", overflowX: "auto" }}>
            {node.formula}
          </pre>
        </div>
        );
      })()}

      {/* REJECTED / DEFERRED PRIMITIVES — what isn't included and why */}
      <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderLeft: `3px solid ${C.muted}`, borderRadius: 6 }}>
        <div onClick={() => setShowRejected(v => !v)} style={{ cursor: "pointer", padding: "10px 14px", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <div>
            <span style={{ fontSize: 9.5, color: C.muted, background: `${C.muted}18`, border: `1px solid ${C.muted}44`, padding: "1px 7px", borderRadius: 3, letterSpacing: 0.5, fontFamily: "ui-monospace,monospace", fontWeight: 700 }}>REJECTED / DEFERRED</span>
            <span style={{ fontSize: 13, color: C.text, fontWeight: 600, marginLeft: 10 }}>Primitives considered and not adopted</span>
          </div>
          <span style={{ fontSize: 14, color: C.muted }}>{showRejected ? "−" : "+"}</span>
        </div>
        {showRejected && (
          <div style={{ padding: "0 14px 14px", borderTop: `1px solid ${C.border}` }}>
            <div style={{ fontSize: 12, color: C.textDim, lineHeight: 1.6, marginTop: 10, marginBottom: 12 }}>
              The choice of two primitives is curated. Seven candidates were considered. Three turned out to be <strong style={{ color: C.text }}>derivable</strong> from the primitives and are now shown as derivation nodes in the diagram. Four are genuinely outside the derivation hierarchy — either open questions or rival primitives — and are shown in the OUTSIDE DERIVATION band, dashed and disconnected from the derivation edges.
            </div>

            {/* Group 1: derivable */}
            <div style={{ fontSize: 10, color: C.muted, fontWeight: 700, letterSpacing: 0.6, marginBottom: 6, fontFamily: "ui-monospace,monospace" }}>
              DERIVABLE — promoted into the diagram as derivation nodes
            </div>
            <div style={{ display: "flex", flexDirection: "column", gap: 6, marginBottom: 14 }}>
              {REJECTED_PRIMITIVES.filter(r => r.shownInDiagram === "derivation").map((r, i) => (
                <div key={i} style={{ background: C.surface2, borderLeft: `2px solid ${P_BOTH}aa`, padding: "8px 10px", borderRadius: 4 }}>
                  <div style={{ display: "flex", justifyContent: "space-between", gap: 8, flexWrap: "wrap", marginBottom: 3 }}>
                    <span style={{ fontSize: 12, fontWeight: 600, color: C.text }}>{r.name}</span>
                    <span style={{ fontSize: 10, color: P_BOTH, fontFamily: "ui-monospace,monospace", fontWeight: 600 }}>{r.verdict}</span>
                  </div>
                  <div style={{ fontSize: 11.5, color: C.textDim, lineHeight: 1.55 }}>{r.reason}</div>
                </div>
              ))}
            </div>

            {/* Group 2: external — open / rival */}
            <div style={{ fontSize: 10, color: C.muted, fontWeight: 700, letterSpacing: 0.6, marginBottom: 6, fontFamily: "ui-monospace,monospace" }}>
              OUTSIDE DERIVATION — open questions and rival primitives, shown in the diagram with dashed borders
            </div>
            <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
              {REJECTED_PRIMITIVES.filter(r => r.shownInDiagram === "external").map((r, i) => {
                // Color-code by external kind: CT rival uses C.con, others use C.muted
                const isRival = r.name.startsWith("Possibility");
                const accentCol = isRival ? C.con : C.muted;
                return (
                  <div key={i} style={{ background: C.surface2, borderLeft: `2px solid ${accentCol}`, padding: "8px 10px", borderRadius: 4 }}>
                    <div style={{ display: "flex", justifyContent: "space-between", gap: 8, flexWrap: "wrap", marginBottom: 3 }}>
                      <span style={{ fontSize: 12, fontWeight: 600, color: C.text }}>{r.name}</span>
                      <span style={{ fontSize: 10, color: accentCol, fontFamily: "ui-monospace,monospace", fontWeight: 600 }}>{r.verdict}</span>
                    </div>
                    <div style={{ fontSize: 11.5, color: C.textDim, lineHeight: 1.55 }}>{r.reason}</div>
                  </div>
                );
              })}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

// ─── RESEARCHING COMPLEX / OPEN SYSTEMS TAB ──────────────────────────────────

const METHOD_COLORS = {
  closure:     "#06b6d4",  // operational closure — cyan (SR-aligned)
  flow:        "#0d9488",  // flow tracking — teal (process-aligned)
  intervene:   "#f97316",  // interventional probing — orange (CI-aligned)
  pattern:     "#eab308",  // pattern compression — yellow (IT-aligned)
  mechanism:   "#166534",  // generative mechanisms — CR-green
  reflexive:   "#0891b2",  // reflexivity — CYB-blue
};

const PROTOMETHODS = [
  {
    id: "closure",
    label: "Operational Closure",
    color: METHOD_COLORS.closure,
    lineage: "Luhmann · Maturana & Varela (autopoiesis) · Cybernetics 2nd order",
    opening: "Don't ask where the system ends. Ask what operation reproduces itself.",
    when: "When a system has no clean spatial coherence but clear operational coherence — finance, science, law, gossip, AI development.",
    how: `Identify the constitutive operation — what does the system do that produces more of the same kind of doing?\n\n• Cells reproduce metabolism\n• Brains reproduce neural signaling\n• Economic systems reproduce payments (Luhmann)\n• Scientific systems reproduce publications\n• Legal systems reproduce legal decisions\n• AI development reproduces training-evaluation-deployment cycles\n\nThe system exists wherever this operation closes on itself. A bank in Tokyo and a bank in Frankfurt are part of the same financial system because the same transactional operations close across them — geography is irrelevant.`,
    operationalize: `1. Name the candidate operation precisely (transactions, communications, decisions).\n2. Identify which acts ARE instances of the operation and which aren't (decision criterion).\n3. Trace closure: does operation O at time t1 produce conditions that enable operation O at time t2?\n4. Map the operational network: who/what participates in the operation?\n5. Look for self-stabilizing patterns — the operation defending and reproducing its own conditions.`,
    example: `**Studying "the scientific community":**\n\nBoundary-thinking fails: scientists are in universities, companies, governments, NGOs, retired, etc.\n\nOperational closure asks: what operation reproduces itself? Answer: peer-reviewed publication. A "scientist" for system purposes is anyone whose communications enter and exit through peer review. Wherever publication-citation-revision cycles close, the science system extends.\n\nThis dissolves the boundary problem: a corporate researcher publishing in journals IS inside; a tenured professor doing no peer-reviewed work IS at the periphery. The operation does the individuation, not geography or institutional affiliation.`,
    limit: "Circular at the edges — defining the operation already presupposes which system you're studying. Best paired with another method as a check.",
  },
  {
    id: "flow",
    label: "Flow Tracking",
    color: METHOD_COLORS.flow,
    lineage: "Process philosophy (Whitehead, Bergson, Dupré) · Thermodynamics · Ulanowicz ascendency · Urban metabolism",
    opening: "Don't define the system. Pick a flow and follow it.",
    when: "When you can identify a conserved or persistent quantity — energy, matter, information, money, attention — that moves through the phenomenon.",
    how: `Choose one of several flow types — different flows reveal different systems:\n\n• **Energy** — ecological food webs, urban energy use, thermodynamic dissipation\n• **Matter** — biogeochemical cycles, supply chains, plastic in oceans\n• **Information** — transfer entropy networks, citation flows, gossip propagation\n• **Money/value** — capital flows, remittances, market dependencies\n• **Attention** — media, platforms, salience economy\n\nThe "system" emerges as the closure pattern: cycles, sinks, sources, dissipative structures, throughput bottlenecks.\n\nFlows are observer-independent. You don't have to commit to where the system is; you measure where the throughput is.`,
    operationalize: `1. Pick a single flow type to start (mixing makes analysis incoherent).\n2. Identify source(s), sink(s), and intermediate transformations.\n3. Quantify throughput at each node.\n4. Find cycles (positive feedback) and dissipation points.\n5. Find which structures persist because of the flow — they are downstream of the flow, not pre-existing entities containing it.\n6. Compare to alternative flow types: same boundary or different?`,
    example: `**Studying "a city":**\n\nDifferent flows give different cities:\n\n• Energy flow → city is a metabolic system extending into power plants, mines, oil fields (hundreds of km)\n• Information flow → city is a network of communications extending globally via fiber\n• Capital flow → city is nodes in international finance, headquarters and back offices distributed\n• Daily commute flow → city is the metropolitan area\n• Cultural flow → city is its global diaspora\n\nNone of these is "wrong." Each is the right city for a particular question. The "boundary problem" of the city dissolves into a methodological choice about which flow you care about.`,
    limit: "Different flows produce different 'systems.' Multi-flow integration is genuinely hard. Some social phenomena resist flow quantification (meanings, norms).",
  },
  {
    id: "intervene",
    label: "Interventional Probing",
    color: METHOD_COLORS.intervene,
    lineage: "Pearl (do-calculus) · Hoel (causal emergence) · Rubin (potential outcomes) · RCT tradition",
    opening: "Don't analyze. Intervene and trace the response.",
    when: "When you can do experiments, natural experiments, or A/B tests — or when policy changes / exogenous shocks give you de facto interventions.",
    how: `Pearl: causation is asymmetric dependency under intervention. P(Y | do(X)) ≠ P(Y | X) in general.\n\nThe functional system IS whatever your intervention propagates through. Not pre-defined — discovered through intervention.\n\nReal sources of intervention:\n• Designed experiments (lab science)\n• Randomized controlled trials (medicine, policy)\n• A/B tests (tech platforms)\n• Natural experiments (policy changes, court rulings)\n• Exogenous shocks (pandemics, wars, technological disruption)\n• Difference-in-differences (econometrics)\n\nThis gives you question-specific systems, not a universal individuation. The "education system" probed via funding changes vs probed via curriculum changes will look different — and both answers are correct for their question.`,
    operationalize: `1. Specify the intervention precisely (what is being set to what value).\n2. Identify direct and indirect downstream variables (Hoel's causal graph mindset).\n3. Measure propagation magnitude and lag.\n4. Map what responds (in the system) vs what doesn't (out of the system) for this intervention.\n5. Iterate: try interventions at different points. Does the system look the same?\n6. Combine multiple interventions for triangulation.`,
    example: `**Studying "the monetary system":**\n\nDon't try to define it abstractly. Intervene: central bank raises interest rate by 25 bps.\n\nWhat moves? Bond yields, mortgage rates, stock prices, currency, eventually unemployment, inflation. Each propagation path is a causal pathway through the monetary system. Whatever didn't respond (technology stock prices in dollars but not yen-denominated, perhaps) lies outside the system for THIS intervention.\n\nNow change to a different intervention: bank capital requirements raised. Different propagation. Now you have two functional systems for monetary policy — and the overlap is the most robust functional core.`,
    limit: "Real interventions are rarely clean. Observational data underdetermines causal structure. Some systems (climate, civilizations) can't be intervened on meaningfully — only observed through history.",
  },
  {
    id: "pattern",
    label: "Pattern Compression",
    color: METHOD_COLORS.pattern,
    lineage: "Dennett (real patterns) · Solomonoff/Kolmogorov (AIT) · Crutchfield (ε-machines) · MDL · Modern ML representation learning",
    opening: "Don't bound. Find what compresses prediction.",
    when: "When you have large amounts of data and want to discover structure without committing to a theoretical decomposition in advance.",
    how: `A real pattern exists wherever describing data through the pattern is shorter than describing data raw:\n\n  K(data | pattern) + K(pattern) < K(data)\n\nThis is operational, not metaphysical. The pattern is real to the degree it earns its description cost in predictive compression.\n\nApplied to human/social data:\n• "Personality trait" is real iff knowing it compresses predictions across contexts\n• "Class structure" is real iff it compresses predictions about economic and political behavior beyond individual variables\n• "National culture" is real to the degree it compresses cross-national prediction\n• "Recession" is real to the degree it compresses cross-sector economic dynamics\n\nDoesn't require boundaries. A pattern can be real even if spatially distributed, intermittent, or overlapping with other patterns. Modern ML representation learning is essentially this method industrialized.`,
    operationalize: `1. Collect data spanning the candidate phenomenon.\n2. Apply compression-based discovery: clustering, dimensionality reduction, ε-machine reconstruction, sparse coding, deep representation learning.\n3. Validate: does the pattern compress predictions on held-out data?\n4. Compare candidate compressions (Occam): shorter total description (pattern + residual) wins.\n5. Check robustness: same pattern across resampling, subgroups, time periods?\n6. Look for cross-scale persistence — patterns that compress at multiple scales are more robust.`,
    example: `**Studying "personality":**\n\nDon't pre-define personality theoretically. Take millions of self-report responses, behavioral observations, language samples.\n\nApply dimensionality reduction. The Big Five (Openness, Conscientiousness, Extraversion, Agreeableness, Neuroticism) emerges as a compressing pattern — these five dimensions reproduce most of the variance in behavior across contexts.\n\nThe Big Five is "real" in Dennett's sense: K(behavioral data | Big Five scores) + K(Big Five framework) < K(behavioral data alone). Personality types like MBTI fail this test — they don't compress as well as the continuous Big Five.\n\nNo boundary needed. The pattern is real wherever it compresses, without specifying who's "in" the personality system.`,
    limit: "Observer-relative in choice of compression scheme and feature space. But this is honest about the relativity, not a hidden assumption.",
  },
  {
    id: "mechanism",
    label: "Generative Mechanism Identification",
    color: METHOD_COLORS.mechanism,
    lineage: "Bhaskar (Critical Realism) · Machamer-Darden-Craver (New Mechanism) · Sociology: Tilly, Hedström",
    opening: "Don't ask what's the system. Ask what mechanisms produce these tendencies.",
    when: "When you can't close conditions (almost all social science), so you'll never see clean regularities — only tendencies under varying interference.",
    how: `Critical Realism's key insight: social systems are *open* — multiple mechanisms operate simultaneously, none cleanly isolated. So you don't get laws, you get tendencies (mechanisms that would produce regularities under closure).\n\nMechanism = entities + activities organized to produce a phenomenon.\n\nIdentify mechanisms by:\n1. Looking for the same outcome across very different surface conditions (mechanism robust to interference)\n2. Looking for outcome failure when a candidate mechanism is absent (necessary condition)\n3. Tracing the *process* by which the mechanism operates (not just the input-output correlation)\n\nMechanisms can be at any level: psychological (status anxiety), institutional (rent extraction), network (preferential attachment), evolutionary (selection on heritable variation).`,
    operationalize: `1. Specify the phenomenon precisely (e.g., "growing wealth inequality in OECD nations since 1980").\n2. Hypothesize generative mechanisms (capital concentration, network effects, declining union power, tax policy, globalization, technology premium).\n3. For each: identify entities + activities + organization that produces the outcome.\n4. Test by finding cases of varying interference: where does the mechanism produce its signature, where is it overwhelmed?\n5. Combine: the actual outcome usually has multiple mechanisms operating with different weights.\n6. Reject mechanisms that fail their signature test — they're at best contributing factors, not generative.`,
    example: `**Studying "political polarization":**\n\nDon't ask "what is the polarization system?" — open, no clean boundary.\n\nAsk: what mechanisms generate the tendency toward polarization?\n\nCandidate mechanisms:\n• Algorithmic content selection on platforms (filter bubbles)\n• Geographic sorting (Bishop's "Big Sort")\n• Affective partisanship (in-group identity)\n• Media business model (engagement = outrage)\n• Elite cue-taking by voters\n\nFor each, identify entities + activities + organization. Test by finding cases of low polarization (different platforms, different demographics, historical comparisons). Mechanisms whose signature appears even in low-polarization contexts (just with weaker effect) are likely real generative mechanisms. Mechanisms absent in low-polarization cases were correlated but not generative.`,
    limit: "Mechanism identification is partly hermeneutic — what counts as the 'real' mechanism is theoretically loaded. Different traditions identify different mechanisms in the same data.",
  },
  {
    id: "reflexive",
    label: "Reflexive Observation",
    color: METHOD_COLORS.reflexive,
    lineage: "von Foerster (2nd-order cybernetics) · Bateson · Phenomenology (Husserl, Merleau-Ponty) · Hermeneutics · Ethnography",
    opening: "You are inside what you study. Design around this fact rather than apologize for it.",
    when: "Always, for human/social systems. Hard sciences can fake observer-neutrality; social science cannot. This is a structural constraint, not a methodological flaw.",
    how: `Three operations:\n\n**1. Phenomenological epoché (Husserl)** — explicitly bracket naturalistic assumptions and describe how the phenomenon presents itself in experience. What does this look like FROM INSIDE the system?\n\n**2. Second-order observation (von Foerster)** — observe the observer. How is the act of observation altering what's observed? Whose perspective is the analysis taking, and what does that perspective miss?\n\n**3. Hermeneutic circle** — meanings can only be understood within their interpretive context. Iterate: provisional interpretation → check against parts → revise → check again. Closure is asymptotic, not achievable.\n\nThis is not anti-rigorous. It's rigor about a different kind of object — one where the investigator is constitutively involved.`,
    operationalize: `1. Name your position explicitly (researcher's standpoint, demographics, theoretical commitments).\n2. Try to articulate the phenomenon from the perspectives of multiple participants (not just analysts).\n3. Trace how your investigation changes what's being investigated (observer effect at social scale).\n4. Iterate interpretation: initial reading → tested against fine-grained instances → revised → tested again.\n5. Combine first-person, second-person (interview), and third-person (statistical) data.\n6. Always pair with at least one non-reflexive method (closure, flow, intervention, pattern, mechanism) to avoid pure interpretivism.`,
    example: `**Studying "anti-establishment political movements":**\n\nThird-person analysis: socioeconomic correlates, network structure, media patterns. Useful but partial.\n\nReflexive layer:\n• How are members understanding their own movement from inside?\n• How does the framing "anti-establishment" itself position the researcher (presumably establishment) and obscure how movement members see themselves?\n• Does the very act of academic study constitute the movement as a stable object of analysis when it experientially feels (to insiders) like a fluid process?\n• What are researchers from inside such movements seeing that outside analysts miss?\n\nThis isn't relativism. It's recognition that the third-person analytic frame has blind spots specifically because the analyst is positioned within larger structures the movement is reacting to. Add the reflexive layer, then combine with one of the other four methods for triangulation.`,
    limit: "Risks pure interpretivism — losing the ability to test claims against external evidence. Must be combined with at least one analytic method. Don't use alone.",
  },
];

const QUESTION_ROUTING = [
  { q: "What is this system doing?",         m: "closure",    note: "Identify the constitutive operation" },
  { q: "Where does X reach in the system?",  m: "flow",       note: "Track the specific flow type" },
  { q: "Where does X reach in the system?",  m: "intervene",  note: "Intervene and trace propagation" },
  { q: "What's the underlying structure?",   m: "pattern",    note: "Find what compresses prediction" },
  { q: "Why does this tendency exist?",      m: "mechanism",  note: "Identify generative mechanisms" },
  { q: "How do participants understand it?", m: "reflexive",  note: "Phenomenology + 2nd-order observation" },
  { q: "Who counts as part of the system?",  m: null,         note: "Wrong question for human/social systems — replace with one of the above" },
];

function ResearchOpenSystemsTab() {
  const [sel, setSel] = useState("closure");
  const m = PROTOMETHODS.find(x => x.id === sel);

  return (
    <div style={{ padding: "20px 24px 60px", maxWidth: 920, margin: "0 auto" }}>

      {/* Intro */}
      <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 8, padding: "14px 18px", marginBottom: 14 }}>
        <div style={{ fontSize: 15, fontWeight: 600, color: C.text, marginBottom: 6 }}>
          Researching Complex / Open Systems
        </div>
        <div style={{ fontSize: 12.5, color: C.textDim, lineHeight: 1.65 }}>
          For systems like humans, societies, and global infrastructures, the standard{" "}
          <span style={{ color: C.text }}>"find the boundary" </span>
          opening fails. These systems lack clean spatial individuation — a person extends into tools and
          relationships; a society has no perimeter. The methodological shift:{" "}
          <span style={{ color: C.text }}>stop trying to bound the system, start tracking what it does.</span>
        </div>
        <div style={{ fontSize: 12.5, color: C.textDim, lineHeight: 1.65, marginTop: 10 }}>
          Six protomethodologies below. None alone is sufficient — they're complementary, each answering a
          different kind of question. Click any method to read its logic, when to use it, how to operationalize,
          and a worked example.
        </div>
      </div>

      {/* Method picker */}
      <div style={{ display: "flex", flexWrap: "wrap", gap: 6, marginBottom: 14 }}>
        {PROTOMETHODS.map(p => {
          const active = p.id === sel;
          return (
            <button key={p.id} onClick={() => setSel(p.id)}
              style={{
                background: active ? `${p.color}1c` : C.surface,
                border: `1px solid ${active ? p.color : C.border}`,
                borderLeft: `3px solid ${p.color}`,
                color: active ? p.color : C.text,
                padding: "8px 12px", fontSize: 12, fontWeight: active ? 600 : 500,
                borderRadius: 5, cursor: "pointer", fontFamily: "inherit",
                transition: "all 100ms",
              }}>
              {p.label}
            </button>
          );
        })}
      </div>

      {/* Selected method panel */}
      {m && (
        <div style={{
          background: C.surface,
          border: `1px solid ${m.color}55`,
          borderLeft: `3px solid ${m.color}`,
          borderRadius: 6, marginBottom: 14, overflow: "hidden",
        }}>
          <div style={{ padding: "12px 18px", borderBottom: `1px solid ${C.border}`, background: `${m.color}07` }}>
            <div style={{ fontSize: 16, fontWeight: 600, color: m.color, marginBottom: 4 }}>{m.label}</div>
            <div style={{ fontSize: 10.5, color: C.muted, fontFamily: "ui-monospace,monospace", letterSpacing: 0.3 }}>
              {m.lineage}
            </div>
          </div>

          <div style={{ padding: "14px 18px" }}>
            {/* Opening move */}
            <Section color={m.color} label="OPENING MOVE">
              <div style={{ fontSize: 13.5, color: C.text, fontStyle: "italic", lineHeight: 1.6 }}>
                {m.opening}
              </div>
            </Section>

            {/* When to use */}
            <Section color={m.color} label="WHEN TO USE">
              <div style={{ fontSize: 12.5, color: C.text, lineHeight: 1.65 }}>{m.when}</div>
            </Section>

            {/* How it works */}
            <Section color={m.color} label="HOW IT WORKS">
              <div style={{ fontSize: 12.5, color: C.text, lineHeight: 1.7, whiteSpace: "pre-line" }}>
                {m.how}
              </div>
            </Section>

            {/* Operationalize */}
            <Section color={m.color} label="OPERATIONALIZE">
              <div style={{ fontSize: 12.5, color: C.text, lineHeight: 1.7, whiteSpace: "pre-line" }}>
                {m.operationalize}
              </div>
            </Section>

            {/* Worked example */}
            <Section color={m.color} label="WORKED EXAMPLE">
              <div style={{
                fontSize: 12.5, color: C.text, lineHeight: 1.7, whiteSpace: "pre-line",
                background: C.surface2, border: `1px solid ${C.border}`,
                borderLeft: `2px solid ${m.color}`,
                padding: "10px 12px", borderRadius: 4,
              }}>
                {m.example.split('**').map((part, i) => i % 2 === 1 ? <strong key={i} style={{ color: m.color }}>{part}</strong> : part)}
              </div>
            </Section>

            {/* Limit */}
            <Section color={m.color} label="LIMIT" last>
              <div style={{ fontSize: 12, color: C.muted, fontStyle: "italic", lineHeight: 1.55 }}>
                {m.limit}
              </div>
            </Section>
          </div>
        </div>
      )}

      {/* Question routing table */}
      <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 8, padding: "14px 18px", marginBottom: 14 }}>
        <div style={{ fontSize: 14, fontWeight: 600, color: C.text, marginBottom: 4 }}>
          Question routing — which method for which question?
        </div>
        <div style={{ fontSize: 11.5, color: C.muted, marginBottom: 10 }}>
          Match the question to the method. The last row is the trap.
        </div>
        <div style={{ overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 12.5 }}>
            <thead>
              <tr style={{ borderBottom: `1px solid ${C.border}` }}>
                <th style={{ textAlign: "left", padding: "7px 10px", color: C.muted, fontWeight: 600, fontSize: 11, textTransform: "uppercase", letterSpacing: 0.5 }}>Question</th>
                <th style={{ textAlign: "left", padding: "7px 10px", color: C.muted, fontWeight: 600, fontSize: 11, textTransform: "uppercase", letterSpacing: 0.5 }}>Method</th>
                <th style={{ textAlign: "left", padding: "7px 10px", color: C.muted, fontWeight: 600, fontSize: 11, textTransform: "uppercase", letterSpacing: 0.5 }}>Core move</th>
              </tr>
            </thead>
            <tbody>
              {QUESTION_ROUTING.map((row, i) => {
                const meth = row.m ? PROTOMETHODS.find(p => p.id === row.m) : null;
                const isTrap = !row.m;
                return (
                  <tr key={i} style={{ borderBottom: i === QUESTION_ROUTING.length - 1 ? "none" : `1px solid ${C.border}` }}>
                    <td style={{ padding: "9px 10px", color: isTrap ? "#ef4444" : C.text, fontWeight: isTrap ? 600 : 400 }}>
                      {row.q}
                    </td>
                    <td style={{ padding: "9px 10px" }}>
                      {meth ? (
                        <button onClick={() => setSel(meth.id)}
                          style={{ background: `${meth.color}1c`, color: meth.color, border: `1px solid ${meth.color}55`, padding: "2px 9px", borderRadius: 4, fontSize: 11, fontWeight: 600, cursor: "pointer", fontFamily: "inherit" }}>
                          {meth.label}
                        </button>
                      ) : (
                        <span style={{ color: "#ef4444", fontSize: 11, fontWeight: 600, textTransform: "uppercase", letterSpacing: 0.5 }}>Trap</span>
                      )}
                    </td>
                    <td style={{ padding: "9px 10px", color: C.textDim, fontSize: 12 }}>{row.note}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      {/* Meta-stance */}
      <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 8, padding: "14px 18px", marginBottom: 14 }}>
        <div style={{ fontSize: 14, fontWeight: 600, color: C.text, marginBottom: 8 }}>
          The meta-stance: pluralist by design
        </div>
        <div style={{ fontSize: 12.5, color: C.text, lineHeight: 1.7 }}>
          For human/social systems, <span style={{ color: C.text, fontWeight: 600 }}>no single methodology is sufficient.</span>{" "}
          Different methodologies answer different questions, and they're not commensurable in a way that lets you
          rank them globally. The competent researcher uses{" "}
          <span style={{ color: C.sr, fontWeight: 600 }}>multiple methods in parallel</span> and triangulates.
        </div>
        <div style={{ fontSize: 12.5, color: C.text, lineHeight: 1.7, marginTop: 10 }}>
          Two non-negotiables for human/social systems specifically:
        </div>
        <ul style={{ margin: "8px 0 0 0", paddingLeft: 22, fontSize: 12.5, color: C.text, lineHeight: 1.7 }}>
          <li><span style={{ fontWeight: 600 }}>Reflexivity:</span> you are inside what you study. Hard sciences can fake observer-neutrality; social science cannot. Build this in from the start.</li>
          <li style={{ marginTop: 6 }}><span style={{ fontWeight: 600 }}>Multi-temporal scales:</span> human systems operate at seconds (attention), days (decisions), years (careers), decades (institutions), centuries (cultures). Track at least three temporal scales.</li>
        </ul>
      </div>

      {/* Constraints still matter footnote */}
      <div style={{
        background: `${C.accent}0a`, border: `1px solid ${C.accent}44`,
        borderLeft: `3px solid ${C.accent}`,
        borderRadius: 6, padding: "12px 16px",
      }}>
        <div style={{ fontSize: 12, color: C.accent, fontWeight: 700, marginBottom: 6, letterSpacing: 0.4, textTransform: "uppercase" }}>
          Note on constraints
        </div>
        <div style={{ fontSize: 12.5, color: C.text, lineHeight: 1.65 }}>
          Constraints still matter — Ashby's law of requisite variety, energy budgets, information bottlenecks, and
          attention bandwidth still apply to human/social systems. What changes is{" "}
          <span style={{ fontWeight: 600 }}>which constraints carry the load.</span> In physical systems,
          spatial/energetic boundaries dominate. In biological systems, metabolic and informational closure dominate.
          In human/social systems, <span style={{ fontWeight: 600 }}>operational, normative, and informational
          constraints dominate</span> — much more than spatial ones. Don't drop constraints. Replace{" "}
          <em>"where is the boundary"</em> with <em>"what closes the operation, what flows are bounded, what
          generative mechanisms apply, what tendencies emerge."</em>
        </div>
      </div>
    </div>
  );
}

function Section({ color, label, children, last }) {
  return (
    <div style={{ marginBottom: last ? 0 : 14 }}>
      <div style={{
        fontSize: 10, fontWeight: 700, letterSpacing: 0.7,
        color: color, marginBottom: 5, textTransform: "uppercase",
        fontFamily: "ui-monospace, monospace",
      }}>
        {label}
      </div>
      {children}
    </div>
  );
}

// ─── SYSTEM TYPES TAB ─────────────────────────────────────────────────────────
// Interactive ontological hierarchy from primitives → social systems.
// Critically refines the original "system_atlas" SVG with sub-types,
// downward causation, information axis, and acknowledged entanglements.

const LEVEL_COLOR = {
  primitive:    "#a78bfa",   // purple — primitives
  set:          "#a78bfa",   // purple — set-theoretic levels
  static:       C.sr,         // cyan — structural realism aligned (L2)
  dynamic:      "#5dcaa5",   // green — dynamical (L3, L4-complex)
  thermo:       "#ef9f27",   // orange — thermodynamic (L4-thermo)
  open:         "#0d9488",   // teal — open systems (L4-open)
  adaptive:     "#65a30d",   // lime — adaptive (L5)
  cognitive:    "#ed93b1",   // pink — cognitive (L6)
  reflexive:    "#be185d",   // magenta — reflexive (L7)
  social:       "#a78bfa",   // purple — social (L8)
};

const SYSTEM_LEVELS = [
  {
    id: "L0", label: "Substrate", symbol: "Bare domain",
    color: LEVEL_COLOR.set,
    status: "placeholder",
    statusNote: "L0 is a formal placeholder, not an instantiable level. By the atlas's own information-theoretic criterion (H=0 ⟺ no structure), L0 has no structural content. Included as the starting point of the construction, not as a kind of system that exists.",
    tagline: "Existence only — no structure yet. Formal placeholder.",
    detail: `The minimal precondition: there is *something*. No distinctions yet, no relations, no time. A bare domain over which questions of structure can be asked but not yet answered.\n\n⚠ This is a formal starting point, not a level of being. By the atlas's own logic, a universe of pure unity is informationally identical to nothing (Shannon entropy of a single-state system is zero). L0 has no natural instances and no physical correlate — the Past Hypothesis in cosmology posits a very specific low-entropy state, which is already L1 or above. L0 exists in the diagram to make the construction visible; treat it as the empty stage before the play begins.`,
    requires: "Nothing (axiomatic starting point)",
    addsNext: "+ Distinction applied",
    examples: "Formal: a name with no referents; an empty set; the pre-distinction void. No physical instance.",
    concepts: [],
  },
  {
    id: "L1", label: "Distinguished set", symbol: "{a, b, c, ...}",
    color: LEVEL_COLOR.set,
    status: "consensus",
    tagline: "Elements that can be told apart. Parts, no relations.",
    detail: `Apply Distinction to the substrate: now there are individuated elements. Each element is distinguishable from each other, but no relations between them are specified.\n\nThis is set theory at its most basic. A bag of marbles where you can tell marble 1 from marble 2, but the relations (which is near which, which came before which) are absent.`,
    requires: "Distinction primitive",
    addsNext: "+ Asymmetric relations between elements",
    examples: "Particles in a gas before interactions; words in a dictionary; pixels in noise",
    concepts: ["distinction", "basic-unit"],
  },
  {
    id: "L2", label: "Structured system", symbol: "G = (V, →E)",
    color: LEVEL_COLOR.static,
    status: "modeling-abstraction",
    statusNote: "L2 has no natural instances — every physical structure is time-extended (L3 or above). Examples cited (periodic table, schemas, frozen graphs) are human artifacts or modeling snapshots. L2 is a useful abstraction for analyzing the relational backbone of a system, not a level of being.",
    tagline: "Static directed graph. Modeling abstraction — every actual structure is time-extended.",
    detail: `Apply Asymmetry to distinguished elements: directed relations appear. Now you have a graph (V, E) where edges have direction. This is the level of *static* structure — schemas, taxonomies, the relational backbone of a system.\n\n⚠ L2 has no natural instances. Every physical structure in the universe is time-extended; a "snapshot" is a representation, not an ontological category. The examples below are all human artifacts (periodic table, database schema) or instantaneous projections of L3 systems (gene network "at one instant"). Treat L2 as a useful abstraction for analyzing relational backbones — the synchronic slice of dynamical systems — not as a kind of system that exists in nature.\n\nThis matters for the atlas's structural-realist commitment: real patterns are time-extended. L2 patterns are real as patterns of L3+ systems.`,
    requires: "L1 + Asymmetry primitive",
    addsNext: "+ State evolution in time",
    examples: "All abstractions: Git commit graph (frozen), periodic table, database schema, gene regulatory network at one instant. No natural instance exists.",
    concepts: ["relation", "asymmetry-direction", "real-pattern"],
  },
  {
    id: "L3", label: "Dynamical system", symbol: "x(t₁) → x(t₂)",
    color: LEVEL_COLOR.dynamic,
    status: "atlas-position",
    statusNote: "\"L3 is time-symmetric\" holds for Hamiltonian/unitary dynamics specifically. Classical dissipative deterministic chaos (Lorenz) is dynamical but not time-symmetric. The L3-vs-L4-thermo boundary for quantum systems via decoherence is interpretation-dependent. The atlas treats L3 as the Hamiltonian/unitary case; other dynamical regimes don't fit cleanly.",
    tagline: "Time enters as ordering. State evolves — reversibility holds for Hamiltonian/unitary L3 specifically.",
    detail: `Apply temporal ordering: states change. The system has a notion of "next state" via a flow φᵗ : X → X or a map x(t+1) = f(x(t)).\n\n**Critical refinement: this is "ordering time," not "thermodynamic time."** Time at L3 is a parameter or sequence index. Direction is undetermined — the arrow of time doesn't enter until L4-Thermodynamic. L3 is the locus of *time-symmetric* dynamics: equations invariant under t → -t.\n\nExamples that fit L3 with reversible time:\n• Frictionless pendulum (Hamiltonian)\n• Conservative N-body system\n• Schrödinger evolution (quantum unitary)\n• Chess game (move-undo possible)\n\n⚠ **Boundary cases the atlas glosses:**\n• Classical dissipative chaos (Lorenz attractor, damped oscillators) has positive Kolmogorov–Sinai entropy and produces information even with deterministic laws; not time-symmetric in any practical sense. Sits awkwardly between L3 and L4-thermo.\n• The L3→L4-thermo bridge via quantum decoherence is interpretation-dependent. Everett, GRW, Bohmian, and QBism interpretations give different stories about where in the hierarchy quantum systems "really" live.\n\n**Noether's theorem operates at L3.** Continuous symmetries of the dynamical law produce conserved quantities: time-translation symmetry → energy conservation; spatial → momentum; rotational → angular momentum. Note this is about laws being the same at different times — NOT about time having direction. Symmetric laws can still grow an arrow at L4-thermo via boundary conditions.\n\n**Quantum mechanics lives at L3.** Schrödinger evolution |ψ(t)⟩ = U(t)|ψ(0)⟩ is unitary, reversible, time-symmetric. The transition from L3 to L4-thermo for quantum systems is precisely decoherence — environmental coupling that makes coherences decay irreversibly.`,
    requires: "L2 + temporal ordering (sequence, parameter time)",
    addsNext: "Three orthogonal upgrades — arrow of time enters at L4-thermo",
    examples: "Pendulum (frictionless), Schrödinger evolution, conservative N-body system, Hamiltonian flow, chess game in progress",
    concepts: ["transformation", "attractor-basin", "real-pattern"],
  },
  {
    id: "L4-thermo", label: "Thermodynamic system", symbol: "dS/dt ≥ 0",
    color: LEVEL_COLOR.thermo, branch: "L4",
    status: "consensus",
    statusNote: "Thermodynamic irreversibility is empirically robust and observer-independent. The deeper question — whether the arrow is fundamental or emergent from time-symmetric laws + Past Hypothesis — is contested in foundations of physics but does not affect this level's status.",
    tagline: "Time gains an arrow. Irreversibility makes evolution one-way at the system level.",
    detail: `**This is where time gains direction.** L3 has time-as-ordering but no arrow. L4-thermo adds the arrow: entropy increases, information is irreversibly lost, the past differs structurally from the future.\n\n**The microscopic→macroscopic puzzle:** the underlying laws (Hamiltonian, Schrödinger) are time-symmetric at L3. The arrow emerges from *boundary conditions*, not laws. A low-entropy initial state + reversible dynamics → effective irreversibility at coarse-grained scales. This is Boltzmann's argument and remains the orthodox account (Albert, Loewer, Wallace).\n\n**Quantum decoherence is the L3→L4-thermo bridge for quantum systems.** Unitary evolution at L3 (reversible) + environmental coupling → exponentially decaying coherences → effective classical, irreversible dynamics at L4-thermo. The "measurement problem" is precisely this transition.\n\nLandauer's principle ties this to information: erasing one bit dissipates at least kT·ln(2) of heat. Irreversibility has a thermodynamic floor.`,
    requires: "L3 + boundary conditions that break time-reversal symmetry",
    addsNext: "Combines with L4-Complex and L4-Open to enable L5",
    examples: "Steam engine, falling rock with friction, isolated chemical reaction approaching equilibrium, decohering quantum system",
    concepts: ["dissipative-structure", "information-entropy"],
  },
  {
    id: "L4-complex", label: "Complex system", symbol: "EI(M) > EI(μ)",
    color: LEVEL_COLOR.dynamic, branch: "L4",
    status: "contested",
    statusNote: "EI is one operationalization of complexity among several. Hoel's causal emergence faces critiques (Dewhurst 2021, Eberhardt-Lee) on coarse-graining sensitivity and the uniform-intervention prior. Other measures (Cμ, Φ, logical depth, effective complexity) capture different aspects. The atlas chooses EI as the marker; this is a position.",
    tagline: "Macro-level causal structure that cannot be reduced to micro. EI is the atlas's chosen marker — alternatives below.",
    detail: `Apply emergence to a dynamical system: macro-level descriptions become causally privileged. Effective Information at the macro scale exceeds EI at the micro scale (Hoel). Real patterns become irreducible — not just convenient.\n\n⚠ **EI is one operationalization among several.** Listing the major alternatives the atlas considers and why EI was chosen:\n\n• **Effective Information (Hoel)** — interventional, computable on causal graphs. ATLAS CHOICE. Critique: depends on a uniform intervention prior; sensitive to coarse-graining; Dewhurst (2021) and others argue the resulting causation is "thin."\n\n• **Statistical Complexity Cμ (Crutchfield)** — entropy of causal states (equivalence classes of histories with identical conditional futures). Objectively privileged structural level. More principled than EI in some ways but harder to compute for high-dimensional systems.\n\n• **Integrated Information Φ (Tononi)** — irreducible interdependence; cannot decompose into independent parts. Foundational to IIT (consciousness theory). Heavily contested mathematically (Mediano et al.) and conceptually (Aaronson).\n\n• **Logical Depth (Bennett)** — computational time to construct from shortest program. Captures organized history. Closely related to assembly index (Walker-Cronin).\n\n• **Effective Complexity (Gell-Mann)** — Kolmogorov complexity of the regularities (not the random part). Separates structure from noise.\n\n**Critical:** Pure L4-Complex without irreversibility is rare. Most cellular automata are complex but reversible at the rule level; their interesting complexity emerges because we ignore the rule's reversibility and focus on coarse-grained dynamics. In practice, complex systems are usually also thermodynamic.`,
    requires: "L3 + emergence (causal autonomy at higher level)",
    addsNext: "Combines with L4-Thermo and L4-Open to enable L5",
    examples: "Flock of starlings, stock market, neural network at inference, cellular automaton, traffic flow",
    concepts: ["emergence-general", "emergence-general", "causal-emergence", "real-pattern"],
  },
  {
    id: "L4-open", label: "Open system", symbol: "∂U ≠ 0",
    color: LEVEL_COLOR.open, branch: "L4",
    status: "consensus",
    statusNote: "Open systems exchanging with environment is a well-established concept (Bertalanffy, Prigogine). Markov-blanket formalization is contested (Aguilera et al. 2022 show non-uniqueness in stochastic systems); the underlying ontology is not.",
    tagline: "Exchanges matter/energy/information with environment. Has a non-trivial boundary.",
    detail: `Apply boundary exchange to a dynamical system: matter, energy, or information flows in and out. The system has a non-trivial relationship with its environment — sources and sinks rather than closure.\n\nThe Markov blanket formalism (Friston) tries to formalize this: a subset of variables that separates internal from external states. **But:** Aguilera et al. (2022) show these blankets may be non-unique or non-existent in stochastic systems. Open systems are real; their boundaries are often genuinely fuzzy.`,
    requires: "L3 + boundary exchange",
    addsNext: "Combines with L4-Thermo and L4-Complex to enable L5",
    examples: "City, flame, firm with revenue and expenses, biological cell, ecosystem",
    concepts: ["boundary", "markov-blanket", "dissipative-structure", "boundary"],
  },
  {
    id: "L5", label: "Adaptive system", symbol: "f_{t+1} = update(f_t, feedback)",
    color: LEVEL_COLOR.adaptive,
    status: "atlas-position",
    statusNote: "The conjunction claim (\"requires all three L4 properties simultaneously\") is a strong heuristic but admits real edge cases: RL agents in simulation lack a direct thermodynamic floor; closed-system selection (e.g., a finite-variant chemical pool) can show adaptation without ongoing energy exchange. The deeper requirement is a directional cost gradient driving selection-like dynamics — thermodynamics is one substrate that supplies it.",
    tagline: "Modifies its own structure in response to environment. Typically requires all three L4 properties — edge cases exist.",
    detail: `Adaptive systems standardly require the *conjunction* of L4-Thermo + L4-Complex + L4-Open:\n\n• Without **irreversibility**, no cost gradient — adaptation has no direction\n• Without **emergence**, no functional organization to adapt\n• Without **openness**, no energy budget — closed systems run down\n\nThis is the load-bearing claim of the original atlas. It is a strong heuristic for adaptive systems instantiated in physical substrates.\n\n⚠ **Edge cases the conjunction claim doesn't cleanly handle:**\n\n• **RL agents inside simulation** lack a real thermodynamic floor (the silicon does; the agent qua agent does not). They still adapt by any operational test. If they are L5, the thermodynamic requirement is delegated to the substrate; if they aren't L5, a huge fraction of contemporary AI research is excluded.\n\n• **Chemical oscillators (BZ reaction)** satisfy all three L4 conditions but most chemists wouldn't call them adaptive. The conjunction is necessary but plausibly not sufficient.\n\n• **The directionality of adaptation** comes from selection (variation + heritability + differential reproduction — see EVO framework), not directly from thermodynamic gradients. Thermodynamics supplies a substrate; selection supplies the direction.\n\n**Revised reading:** the deeper requirement is a *directional cost gradient driving selection-like dynamics*. In physical substrates this is supplied by L4-thermo + L4-open. In simulated or idealized settings the thermodynamic role is delegated to whatever runs the simulation. The original conjunction claim is a useful heuristic in physical systems; treat it as such.\n\n**Living vs adaptive.** Not all adaptive systems are alive. Life standardly requires more: autopoiesis (Maturana-Varela), metabolism (Schrödinger, Kauffman), reproduction with heredity (evolutionary biology). A self-organizing chemical clock is adaptive in some sense but not alive. The atlas does not currently have a separate "Living" level; consider this an L5-living sub-type implicit in the biological examples.`,
    requires: "L4-Thermo + L4-Complex + L4-Open simultaneously (in physical substrates) — or a directional cost gradient + selection dynamics more abstractly",
    addsNext: "+ Internal model of environment",
    examples: "Bacterium, RL agent during training, immune system, evolving species, learning organization",
    concepts: ["self-organization", "free-energy-principle", "tech-evolution", "tech-evolution"],
  },
  {
    id: "L6", label: "Cognitive system", symbol: "p(world | sensory)",
    color: LEVEL_COLOR.cognitive,
    status: "atlas-position",
    statusNote: "The representationalist framing (\"maintains internal model\") is contested by 4E cognition / radical enactivism (Hutto, Myin, Di Paolo), which denies that cognition requires internal representations. The three sub-types listed are not exhaustive; symbolic, hybrid neuro-symbolic, collective, and phylogenetically hardwired cognition also belong here.",
    tagline: "Maintains an internal model of its environment used to predict and act. Representationalist framing — alternatives exist.",
    detail: `Cognitive systems carry an internal representation of their environment, used to predict and act on it. Five sub-types worth distinguishing (the original atlas listed three):\n\n**(a) Statistical / model-based** — Bayesian inference, Kalman filters. Explicit model, explicit update rule.\n\n**(b) Learned / representational** — deep neural networks, LLMs. Implicit model in learned weights, gradient-based update.\n\n**(c) Evolved / embodied** — biological cognition. Model partly in synaptic weights, partly in body morphology, partly in environmental scaffolding (4E cognition — embodied, embedded, extended, enacted).\n\n**(d) Symbolic / GOFAI** — explicit knowledge representation, logic-based inference, expert systems, theorem provers. Model as symbols + rules.\n\n**(e) Collective / distributed** — swarm intelligence, market price discovery, distributed cognition (Hutchins). The cognitive system is the group, not any individual. Model is in collective dynamics.\n\nAlso worth flagging: **phylogenetically hardwired behavior** (sphex wasp, innate releasing mechanisms, evolved heuristics) — model is in the genome and developmental program, not the individual organism's lifetime.\n\n⚠ **Contested framing.** The representationalist picture this hierarchy uses is rejected by 4E cognition / radical enactivism (Hutto, Myin, Di Paolo): cognition is ongoing sensorimotor coupling, not internal model-update. Hybrid neuro-symbolic AI sits between (a) and (d). Plant phototropism as L6 (Trewavas, Calvo) is a minority position — most cognitive scientists would place it at L5.`,
    requires: "L5 + capacity to model environment (or, on enactivist readings, capacity to maintain organism-environment coupling)",
    addsNext: "+ Model includes self (self-reference)",
    examples: "Mouse navigating maze, Kalman filter, LLM at inference, robot with SLAM, theorem prover (GOFAI), ant colony foraging (collective), plant phototropism (boundary case)",
    concepts: ["free-energy-principle", "free-energy-principle", "free-energy-principle", "free-energy-principle"],
  },
  {
    id: "L7", label: "Reflexive system", symbol: "S ⊃ model(S)",
    color: LEVEL_COLOR.reflexive,
    status: "contested",
    statusNote: "The deflationary verdict (\"no extra ontological primitive needed\") is the structural-realist position. Critical Realism, Phenomenology, and Powers metaphysics each hold reflexivity introduces irreducibly novel properties or powers. The hard problem of consciousness is unresolved. The atlas adopts the deflationary reading; this is not a settled finding.",
    tagline: "Self-modeling. Atlas reading: derived from rich asymmetric networks. Major traditions disagree.",
    detail: `Reflexivity emerges when a cognitive system is complex enough to contain a model of itself. The system can ask "what am I doing" and use the answer to change what it's doing.\n\n**Atlas reading (structural-realist):** No extra ontological primitive needed. Reflexivity is a derived property of sufficiently rich asymmetric networks. No "innate powers" beyond physics — but the reflexive organization creates genuinely novel feedback loops where the model influences the modeled.\n\nThis is the strange loop (Hofstadter). It is also the structural ground for self-correction, debugging, metacognition, and many forms of agency.\n\n⚠ **The deflationary verdict is contested.** Major traditions in this atlas's own framework list disagree:\n\n• **Critical Realism (Bhaskar):** each stratum has irreducible powers. Reflexivity introduces new causal powers, not just rearrangements of components.\n\n• **Phenomenology (Husserl, Heidegger, Zahavi, Thompson):** first-person experience is irreducibly novel. No third-person structural description captures what-it-is-like. The hard problem of consciousness (Chalmers) remains.\n\n• **Powers metaphysics (Mumford, Bird, Anjum):** properties ARE powers; reflexive systems exhibit new powers their components lack.\n\n• **Enactivism (Varela, Thompson):** mind is not in the brain alone; reflexivity is constituted through embodied, embedded coupling. The atlas's deflationary reading individualizes reflexivity in ways enactivists reject.\n\nThe atlas's choice preserves naturalism without dualism. The cost: substantive debate about whether something genuinely new appears with self-modeling, or whether sufficiently complex structure suffices, is treated as settled when it is not.`,
    requires: "L6 + self-reference in the model",
    addsNext: "+ Other reflexive systems modeled in turn (social)",
    examples: "Human noticing bias, debugger inspecting itself, scientist reflecting on method, an LLM critiquing its own output",
    concepts: ["reflexive", "self-reference-closure", "observer-reflexivity", "self-reference-closure"],
  },
  {
    id: "L8", label: "Social system", symbol: "S₁ ⊃ model(S₂ ⊃ model(S₁))",
    color: LEVEL_COLOR.social,
    status: "contested",
    statusNote: "The L6 → L7 → L8 ordering presupposes methodological individualism (individual cognition before social embedding). The reverse ordering (Vygotsky, Mead, Bakhtin, ubuntu — \"I am because we are\") holds that individual reflexivity is constituted through social embedding, so L8 precedes L7. The deeper implication: a strictly linear spine may be wrong; a co-emergent or recursive architecture at the top of the hierarchy may be needed.",
    tagline: "Reflexive systems modeling each other. Linear ordering with L7 is methodologically individualist — alternatives exist.",
    detail: `Social systems consist of reflexive agents modeling each other's models. Each agent's behavior depends on what others are predicted to do, which depends on what they predict the agent will do, recursively.\n\nThis recursion is the structural source of common knowledge (Lewis), norms (Bicchieri), strategic interaction (game theory), and culture. Common knowledge is the fixed point of mutual modeling.\n\n⚠ **Contested ordering (L7 ↔ L8).** Two competing pictures:\n\n• **Standard / individualist view:** self-modeling (L7) comes before social embedding (L8). Individual minds, then they encounter each other. The atlas's default ordering.\n\n• **Constitutive social view ("I am because we are"):** reflexivity emerges *from* social embedding. Vygotsky (developmental psych: higher mental functions originate in social interaction). Mead (self as product of generalized other). Bakhtin (dialogical self). Ubuntu philosophy. On this view, L8 precedes L7 — there is no pre-social reflexive individual.\n\n**The deeper implication.** If the constitutive view is right, the linear spine is wrong, not just reversible. Individual cognition would itself be a social product, suggesting a co-emergent or recursive architecture at the top of the hierarchy rather than a clean ladder. The atlas's diagram supports both directions of the L7↔L8 edge as a partial accommodation; a fuller treatment would relax the linearity itself.`,
    requires: "L7 + other reflexive systems present (standard view) — or L7 emerges from L8 (constitutive view)",
    addsNext: "Cultural evolution, institutions, civilizations (not on this spine)",
    examples: "Traders modeling each other, courtroom, research community, language community, market",
    concepts: ["agentic-systems-workflow", "observer-reflexivity", "reflexive", "self-organization"],
  },
];

// Cross-level couplings — downward causation that the original atlas hides
// Cross-level couplings — downward causation that the original atlas hides.
// The atlas treats downward causation as CONSTRAINT-IMPOSITION on lower-level dynamics
// (Juarrero, Hoel, Ellis), NOT direct macro→micro event causation in Kim's sense.
// This is one philosophical reading; Kim's exclusion argument is the standard objection.
const DOWNWARD_EDGES = [
  { from: "L8", to: "L6", label: "Cultural evolution shapes individual cognition", strength: 3 },
  { from: "L7", to: "L4-complex", label: "Self-models modify behavior at the dynamical level", strength: 2 },
  { from: "L7", to: "L4-thermo", label: "Self-regulation alters metabolic state", strength: 2 },
  { from: "L5", to: "L4-thermo", label: "Adaptation channels energy flux", strength: 2 },
  { from: "L8", to: "L8", label: "Social systems are themselves L4-complex (recursive)", strength: 1 },
];

// Information theory threads transversally through the hierarchy.
// Atlas's canonical choice per level + alternative operationalizations to know.
const INFO_AXIS = [
  { level: "L1", quantity: "H(X) — Shannon entropy", note: "Counts distinguishable states. Alternatives: cardinality |X|, Kolmogorov K(X) for individual objects." },
  { level: "L3", quantity: "I(past; future) — predictive info", note: "How much past constrains future (Crutchfield's excess entropy E). Alternatives: Lyapunov spectrum, entropy rate hμ." },
  { level: "L4-thermo", quantity: "Landauer cost (kT ln 2 / bit)", note: "Thermodynamic floor for info erasure. Also: entropy production σ̇, Jarzynski/Crooks fluctuation theorems." },
  { level: "L4-complex", quantity: "EI(M) > EI(μ)  [atlas choice]", note: "Hoel's causal emergence. Alternatives: statistical complexity Cμ (Crutchfield), integrated information Φ (Tononi, contested), logical depth (Bennett), effective complexity (Gell-Mann)." },
  { level: "L4-open", quantity: "TE(env → sys)", note: "Transfer entropy across boundary. Alternatives: directed information I(X^n → Y^n), partial info decomposition (PID)." },
  { level: "L5", quantity: "F[q] — variational free energy  [atlas choice / Friston]", note: "Active inference framing. Alternatives: expected utility, regret bounds (RL), fitness function (EVO), control-theoretic cost J[u]." },
  { level: "L6", quantity: "I(world; model) — modeling accuracy", note: "Mutual info between world and representation. Alternatives: prediction error (predictive coding), Bayesian model evidence p(D|M), reward prediction error (RL)." },
  { level: "L7", quantity: "I(self-model; self) — self-modeling depth", note: "Self-modeling accuracy. Alternatives: Hofstadter strange-loop depth, meta-prediction accuracy, fixed-point structure of S ⊃ model(S)." },
  { level: "L8", quantity: "Common knowledge — fixed point of nested I", note: "Lewis. Alternatives: Aumann agreement theorem, Nash equilibrium / correlated equilibrium concepts, k-th order belief hierarchies (Mertens-Zamir)." },
];

// Coupling axis — perpendicular to the level axis
const COUPLING_NOTE = `**Coupling — a dimension the spine collapses.** A gas at L4 (loosely coupled aggregate) and a brain at L4 (tightly coupled whole) both occupy L4-Complex, but differ enormously in internal coupling strength. Coupling runs perpendicular to the level axis:\n\n• **Loose:** gas, market, random crowd — components weakly correlated\n• **Medium:** ecosystem, firm, polity — modular with cross-module dependencies  \n• **Tight:** cell, brain, integrated organism — components strongly mutually determining\n\nA more complete atlas would be a 2D map: level (vertical) × coupling (horizontal). The current spine compresses coupling into "what level."`;

// Mobile-friendly compact layout. Phases group the hierarchy semantically.
// Box widths are tight; viewBox is narrow; vertical phases are color-banded.
const LEVEL_POSITIONS = {
  L0:           { x: 90,  y: 8   },
  L1:           { x: 90,  y: 78  },
  L2:           { x: 90,  y: 148 },
  L3:           { x: 90,  y: 252 },
  "L4-thermo":  { x: 10,  y: 340 },
  "L4-complex": { x: 110, y: 340 },
  "L4-open":    { x: 210, y: 340 },
  L5:           { x: 90,  y: 410 },
  L6:           { x: 90,  y: 514 },
  L7:           { x: 90,  y: 584 },
  L8:           { x: 90,  y: 654 },
};
const NW = 200, NW_BRANCH = 90, NH = 50;

// Three phases — semantic grouping that makes the spine logic visible
const PHASES = [
  { id: "static",     label: "Static phase",      sublabel: "no time yet — set-theoretic",
    y: 0,   h: 218,  color: "#a78bfa" },
  { id: "dynamical",  label: "Dynamical phase",   sublabel: "time enters · energy · adaptation",
    y: 230, h: 248,  color: "#5dcaa5" },
  { id: "cognitive",  label: "Cognitive phase",   sublabel: "model · self-model · mutual model",
    y: 490, h: 224,  color: "#ed93b1" },
];

// Per-level metadata used by toggles
const LEVEL_TIME_CHAR = {
  "L3":        { glyph: "t ↔", text: "Reversible — ordering time only" },
  "L4-thermo": { glyph: "t →", text: "Irreversible — thermodynamic arrow" },
};
const LEVEL_INFO_QTY = {
  "L1":         "H(X) — counts distinguishable states",
  "L2":         "Mutual info — relational structure",
  "L3":         "I(past; future) — predictive info",
  "L4-thermo":  "Landauer kT·ln(2) — thermodynamic floor",
  "L4-complex": "EI(M) > EI(μ) — atlas choice; alts: Cμ, Φ, logical depth",
  "L4-open":    "TE(env → sys) — boundary transfer",
  "L5":         "F[q] — atlas/Friston choice; alts: expected utility, fitness, control cost",
  "L6":         "I(world; model) — modeling accuracy",
  "L7":         "I(self; self-model) — self-modeling depth",
  "L8":         "Common knowledge — fixed-point of nested I",
};
const LEVEL_DOWNWARD = {
  "L5":  ["L4-thermo"],
  "L7":  ["L4-thermo", "L4-complex"],
  "L8":  ["L6", "L4-complex"],
};

function LevelCard({ L, active, onSelect, jumpToConcept, showTime, showInfo, showDownward, narrow }) {
  const isBranch = L.id.startsWith("L4-");
  const time = LEVEL_TIME_CHAR[L.id];
  const info = LEVEL_INFO_QTY[L.id];
  const downward = LEVEL_DOWNWARD[L.id];
  const statusCol = L.status ? STATUS_COLOR[L.status] : null;
  const statusLab = L.status ? STATUS_LABEL[L.status] : null;

  return (
    <div style={{
      background: active ? `${L.color}10` : C.surface,
      border: `1px solid ${active ? L.color : L.color + "33"}`,
      borderLeft: `3px solid ${L.color}`,
      borderRadius: 6,
      transition: "all 150ms",
      overflow: "hidden",
    }}>
      {/* Always-visible header */}
      <div onClick={() => onSelect(L.id)} style={{ padding: narrow ? "8px 10px" : "10px 13px", cursor: "pointer" }}>
        <div style={{ display: "flex", alignItems: "baseline", gap: 8, flexWrap: "wrap", marginBottom: 3 }}>
          <span style={{ fontSize: 9.5, fontFamily: "ui-monospace,monospace", color: L.color, fontWeight: 700, letterSpacing: 0.4 }}>{L.id}</span>
          <span style={{ fontSize: narrow ? 12 : 13.5, fontWeight: 600, color: C.text }}>{L.label}</span>
          {statusCol && (
            <span style={{ fontSize: 9, color: statusCol, background: `${statusCol}18`, border: `1px solid ${statusCol}44`, padding: "1px 6px", borderRadius: 3, fontFamily: "ui-monospace,monospace", fontWeight: 700, letterSpacing: 0.4 }}>
              {statusLab}
            </span>
          )}
          {showTime && time && (
            <span style={{ fontSize: 10, color: "#9333ea", background: "#9333ea15", border: "1px solid #9333ea44", padding: "1px 6px", borderRadius: 3, fontFamily: "ui-monospace,monospace", fontWeight: 700 }}>
              {time.glyph}
            </span>
          )}
          {showDownward && downward && (
            <span style={{ fontSize: 9.5, color: "#ef4444", background: "#ef444415", border: "1px solid #ef444444", padding: "1px 6px", borderRadius: 3, fontFamily: "ui-monospace,monospace", fontWeight: 700 }}>
              ↓ {downward.join(",")}
            </span>
          )}
        </div>
        <code style={{ fontSize: 10.5, color: C.muted, fontFamily: "ui-monospace,monospace" }}>{L.symbol}</code>
        {!active && (
          <div style={{ fontSize: 11.5, color: C.textDim, lineHeight: 1.5, marginTop: 5 }}>
            {L.tagline}
          </div>
        )}
        {showInfo && info && !active && (
          <div style={{ fontSize: 10.5, color: C.it, fontFamily: "ui-monospace,monospace", marginTop: 4, opacity: 0.85 }}>
            {info}
          </div>
        )}
      </div>

      {/* Expanded detail */}
      {active && (
        <div style={{ padding: "2px 13px 13px" }}>
          <div style={{ fontSize: 12, color: L.color, fontStyle: "italic", marginBottom: 9, lineHeight: 1.5 }}>
            {L.tagline}
          </div>
          {L.statusNote && statusCol && (
            <div style={{ background: `${statusCol}0a`, border: `1px solid ${statusCol}44`, borderLeft: `2px solid ${statusCol}`, borderRadius: 4, padding: "7px 10px", marginBottom: 10, fontSize: 11, lineHeight: 1.55 }}>
              <strong style={{ color: statusCol }}>{statusLab}: </strong>
              <span style={{ color: C.textDim }}>{L.statusNote}</span>
            </div>
          )}
          {showTime && time && (
            <div style={{ background: "#9333ea0a", border: "1px solid #9333ea44", borderLeft: "2px solid #9333ea", borderRadius: 4, padding: "6px 9px", marginBottom: 10, fontSize: 11, color: "#9333ea", lineHeight: 1.5 }}>
              <strong>Time character:</strong> {time.text}
            </div>
          )}
          {showInfo && info && (
            <div style={{ background: C.it + "0a", border: `1px solid ${C.it}44`, borderLeft: `2px solid ${C.it}`, borderRadius: 4, padding: "6px 9px", marginBottom: 10, fontSize: 11, color: C.it, lineHeight: 1.5, fontFamily: "ui-monospace,monospace" }}>
              <strong style={{ fontFamily: "inherit" }}>Info quantity: </strong>{info}
            </div>
          )}
          {showDownward && downward && (
            <div style={{ background: "#ef44440a", border: "1px solid #ef444444", borderLeft: "2px solid #ef4444", borderRadius: 4, padding: "6px 9px", marginBottom: 10, fontSize: 11, color: "#ef4444", lineHeight: 1.5 }}>
              <strong>Downward causation:</strong> shapes {downward.join(", ")} via constraint-imposition (Juarrero/Hoel/Ellis reading)
            </div>
          )}
          <div style={{ fontSize: 12.5, color: C.text, lineHeight: 1.7, whiteSpace: "pre-line", marginBottom: 10 }}>
            {L.detail.split("**").map((p, i) => i % 2 === 1 ? <strong key={i} style={{ color: L.color }}>{p}</strong> : p)}
          </div>
          <div style={{ background: C.surface2, border: `1px solid ${C.border}`, borderRadius: 4, padding: "7px 10px", marginBottom: 10, fontSize: 11, lineHeight: 1.6 }}>
            <div><span style={{ color: C.muted, fontWeight: 600 }}>Requires: </span><span style={{ color: C.text }}>{L.requires}</span></div>
            {L.addsNext && <div style={{ marginTop: 3 }}><span style={{ color: C.muted, fontWeight: 600 }}>Adds next: </span><span style={{ color: C.text }}>{L.addsNext}</span></div>}
          </div>
          <div style={{ marginBottom: L.concepts && L.concepts.length ? 10 : 0 }}>
            <div style={{ fontSize: 9.5, color: C.muted, fontWeight: 700, letterSpacing: 0.6, textTransform: "uppercase", marginBottom: 4 }}>Examples</div>
            <div style={{ fontSize: 11.5, color: C.text, lineHeight: 1.55 }}>{L.examples}</div>
          </div>
          {L.concepts && L.concepts.length > 0 && (
            <div>
              <div style={{ fontSize: 9.5, color: C.muted, fontWeight: 700, letterSpacing: 0.6, textTransform: "uppercase", marginBottom: 5 }}>Related concepts</div>
              <div style={{ display: "flex", flexWrap: "wrap", gap: 4 }}>
                {L.concepts.map(cid => (
                  <button key={cid} onClick={(e) => { e.stopPropagation(); jumpToConcept(cid); }}
                    style={{
                      background: `${L.color}10`, color: L.color,
                      border: `1px solid ${L.color}33`, padding: "2px 7px",
                      borderRadius: 4, fontSize: 10.5, cursor: "pointer", fontFamily: "inherit",
                    }}>
                    {cid}
                  </button>
                ))}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function PhaseHeader({ phase }) {
  return (
    <div style={{
      display: "flex", alignItems: "baseline", gap: 8,
      padding: "12px 4px 6px", marginBottom: 6,
      borderBottom: `1px solid ${phase.color}33`,
    }}>
      <div style={{ width: 4, height: 14, background: phase.color, borderRadius: 1 }} />
      <div style={{ fontSize: 11.5, fontWeight: 700, color: phase.color, letterSpacing: 0.6, textTransform: "uppercase", fontFamily: "ui-monospace,monospace" }}>
        {phase.label}
      </div>
      <div style={{ fontSize: 10.5, color: C.muted, fontStyle: "italic" }}>
        {phase.sublabel}
      </div>
    </div>
  );
}

// Compact diagram in Primitives-tab style — overview map of the hierarchy
// Layout: STATIC phase horizontal across top, DYNAMICAL middle (fork/converge),
// COGNITIVE phase horizontal across bottom. viewBox 720×620 to fit everything with margin.
const SYS_DIAGRAM_POS = {
  // STATIC PHASE — horizontal row at top
  L0:           { x: 90,  y: 40 },
  L1:           { x: 290, y: 40 },
  L2:           { x: 490, y: 40 },
  // DYNAMICAL PHASE — vertical fork in middle
  L3:           { x: 290, y: 165 },
  "L4-thermo":  { x: 60,  y: 280 },
  "L4-complex": { x: 290, y: 280 },
  "L4-open":    { x: 520, y: 280 },
  L5:           { x: 290, y: 405 },
  // COGNITIVE PHASE — horizontal row at bottom
  L6:           { x: 90,  y: 525 },
  L7:           { x: 290, y: 525 },
  L8:           { x: 490, y: 525 },
};
const SYS_NODE_W = 140, SYS_NODE_H = 50;

const SYS_DIAGRAM_EDGES = [
  // Static horizontal flow
  { from: "L0", to: "L1", kind: "horizontal" },
  { from: "L1", to: "L2", kind: "horizontal" },
  // Static → dynamical (top-down)
  { from: "L2", to: "L3", kind: "elbow-down-left" },
  // L3 fork
  { from: "L3", to: "L4-thermo",  kind: "fork-left" },
  { from: "L3", to: "L4-complex", kind: "vertical" },
  { from: "L3", to: "L4-open",    kind: "fork-right" },
  // L4 → L5 converge
  { from: "L4-thermo",  to: "L5", kind: "converge-from-left" },
  { from: "L4-complex", to: "L5", kind: "vertical" },
  { from: "L4-open",    to: "L5", kind: "converge-from-right" },
  // Dynamical → cognitive (top-down to L6)
  { from: "L5", to: "L6", kind: "elbow-down-left" },
  // Cognitive sequence
  { from: "L6", to: "L7", kind: "horizontal" },
  { from: "L7", to: "L8", kind: "horizontal-bidir" },  // contested ordering
];

const SYS_DIAGRAM_PHASES = [
  { id: "static",    label: "STATIC",    yStart: 10,  yEnd: 115, color: PHASES[0].color, note: "no time" },
  { id: "dynamical", label: "DYNAMICAL", yStart: 125, yEnd: 480, color: PHASES[1].color, note: "time · energy · adaptation" },
  { id: "cognitive", label: "COGNITIVE", yStart: 490, yEnd: 605, color: PHASES[2].color, note: "model · self · others" },
];

// Helper: compute edge endpoints (anchoring on node edges, not centers)
function getEdgePoints(fromId, toId, kind) {
  const fp = SYS_DIAGRAM_POS[fromId];
  const tp = SYS_DIAGRAM_POS[toId];
  if (!fp || !tp) return null;

  const fcx = fp.x + SYS_NODE_W / 2;
  const fcy = fp.y + SYS_NODE_H / 2;
  const tcx = tp.x + SYS_NODE_W / 2;
  const tcy = tp.y + SYS_NODE_H / 2;

  if (kind === "horizontal" || kind === "horizontal-bidir") {
    return {
      x1: fp.x + SYS_NODE_W, y1: fcy,
      x2: tp.x,              y2: tcy,
    };
  }
  if (kind === "vertical") {
    return {
      x1: fcx, y1: fp.y + SYS_NODE_H,
      x2: tcx, y2: tp.y,
    };
  }
  if (kind === "fork-left" || kind === "converge-from-left") {
    return {
      x1: kind === "fork-left" ? fcx - 30 : fp.x + SYS_NODE_W,
      y1: kind === "fork-left" ? fp.y + SYS_NODE_H : fcy,
      x2: kind === "fork-left" ? tp.x + SYS_NODE_W : tcx + 30,
      y2: kind === "fork-left" ? tcy : tp.y,
    };
  }
  if (kind === "fork-right" || kind === "converge-from-right") {
    return {
      x1: kind === "fork-right" ? fcx + 30 : fp.x,
      y1: kind === "fork-right" ? fp.y + SYS_NODE_H : fcy,
      x2: kind === "fork-right" ? tp.x : tcx - 30,
      y2: kind === "fork-right" ? tcy : tp.y,
    };
  }
  if (kind === "elbow-down-left") {
    return {
      x1: fcx, y1: fp.y + SYS_NODE_H,
      x2: tcx, y2: tp.y,
    };
  }
  return { x1: fcx, y1: fcy, x2: tcx, y2: tcy };
}

function SystemTypesDiagram({ sel, setSel }) {
  const SVG_W = 720, SVG_H = 645;

  return (
    <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 8, padding: 10, marginBottom: 12 }}>
      <svg viewBox={`0 0 ${SVG_W} ${SVG_H}`} style={{ width: "100%", height: "auto", display: "block" }}>

        {/* Phase bands */}
        {SYS_DIAGRAM_PHASES.map(p => (
          <g key={p.id}>
            <rect x={0} y={p.yStart} width={SVG_W} height={p.yEnd - p.yStart}
              fill={p.color} fillOpacity={0.04} stroke="none" />
            <rect x={0} y={p.yStart} width={3} height={p.yEnd - p.yStart} fill={p.color} opacity={0.45} />
            <text x={12} y={p.yStart + 16} fill={p.color} fontSize={10.5} fontWeight={700}
              letterSpacing={0.6} fontFamily="ui-monospace,monospace">
              {p.label}
            </text>
            <text x={12} y={p.yStart + 30} fill={p.color} fontSize={9.5}
              opacity={0.7} fontFamily="ui-monospace,monospace">
              {p.note}
            </text>
          </g>
        ))}

        {/* L4 cluster bracket */}
        <rect x={50} y={272} width={620} height={SYS_NODE_H + 16} rx={6}
          fill="none" stroke={PHASES[1].color} strokeWidth={0.8} strokeDasharray="3,2" opacity={0.4} />
        <text x={SVG_W / 2} y={355} textAnchor="middle" fill={PHASES[1].color}
          fontSize={10} fontStyle="italic" letterSpacing={0.3}>
          L4 — three orthogonal upgrades · all required for L5
        </text>

        {/* Arrowhead markers */}
        <defs>
          <marker id="sys-arr" viewBox="0 0 10 10" refX="9" refY="5"
            markerWidth="4.5" markerHeight="4.5" orient="auto-start-reverse">
            <path d="M 0 0 L 10 5 L 0 10 z" fill={C.muted} />
          </marker>
          <marker id="sys-arr-down" viewBox="0 0 10 10" refX="9" refY="5"
            markerWidth="5" markerHeight="5" orient="auto-start-reverse">
            <path d="M 0 0 L 10 5 L 0 10 z" fill="#ef4444" />
          </marker>
          {/* Bidirectional arrowhead at start too */}
          <marker id="sys-arr-start" viewBox="0 0 10 10" refX="1" refY="5"
            markerWidth="4.5" markerHeight="4.5" orient="auto">
            <path d="M 0 0 L 10 5 L 0 10 z" fill={C.muted} />
          </marker>
        </defs>

        {/* Spine edges */}
        {SYS_DIAGRAM_EDGES.map((e, i) => {
          const pts = getEdgePoints(e.from, e.to, e.kind);
          if (!pts) return null;
          const isBidir = e.kind === "horizontal-bidir";
          return (
            <line key={i} x1={pts.x1} y1={pts.y1} x2={pts.x2} y2={pts.y2}
              stroke={C.muted}
              strokeWidth={0.9}
              strokeOpacity={0.55}
              markerEnd="url(#sys-arr)"
              markerStart={isBidir ? "url(#sys-arr-start)" : undefined}
            />
          );
        })}

        {/* Bidirectional indicator label between L7 and L8 */}
        <text x={(SYS_DIAGRAM_POS["L7"].x + SYS_NODE_W + SYS_DIAGRAM_POS["L8"].x) / 2}
          y={SYS_DIAGRAM_POS["L7"].y + SYS_NODE_H / 2 - 8}
          textAnchor="middle" fill={C.muted} fontSize={8} fontStyle="italic" opacity={0.8}>
          contested order
        </text>

        {/* Downward causation arcs — contained within viewBox */}
        {[
          { from: "L5", to: "L4-thermo",  side: "left"  },
          { from: "L7", to: "L4-thermo",  side: "left"  },
          { from: "L8", to: "L4-complex", side: "right" },
          { from: "L8", to: "L6",         side: "right" },
        ].map((e, i) => {
          const fp = SYS_DIAGRAM_POS[e.from];
          const tp = SYS_DIAGRAM_POS[e.to];
          // Anchor on far side (left or right) of source/target boxes
          const isLeft = e.side === "left";
          const fx = isLeft ? fp.x : fp.x + SYS_NODE_W;
          const fy = fp.y + SYS_NODE_H / 2;
          const tx = isLeft ? tp.x : tp.x + SYS_NODE_W;
          const ty = tp.y + SYS_NODE_H / 2;
          // Curve outward — clamp control point within SVG
          const cx = isLeft ? Math.max(15, Math.min(fx, tx) - 35) : Math.min(SVG_W - 15, Math.max(fx, tx) + 35);
          return (
            <path key={'dc'+i}
              d={`M ${fx} ${fy} Q ${cx} ${(fy + ty) / 2} ${tx} ${ty}`}
              fill="none" stroke="#ef4444" strokeWidth={1.1}
              strokeOpacity={0.5} strokeDasharray="4,3"
              markerEnd="url(#sys-arr-down)" />
          );
        })}

        {/* Nodes */}
        {SYSTEM_LEVELS.map(L => {
          const p = SYS_DIAGRAM_POS[L.id];
          if (!p) return null;
          const active = sel === L.id;
          const shortLabel = L.label
            .replace(" system", "")
            .replace(" / Direction", "");
          const timeChar = L.id === "L3" ? "t ↔" : L.id === "L4-thermo" ? "t →" : null;
          const statusCol = L.status ? STATUS_COLOR[L.status] : null;
          // Visually dim placeholder/abstraction levels (L0, L2)
          const dimmed = L.status === "placeholder" || L.status === "modeling-abstraction";
          const nodeOpacity = dimmed && !active ? 0.55 : 1;
          return (
            <g key={L.id} onClick={() => setSel(L.id)} style={{ cursor: "pointer" }} opacity={nodeOpacity}>
              <rect x={p.x} y={p.y} width={SYS_NODE_W} height={SYS_NODE_H} rx={7}
                fill={active ? `${L.color}28` : C.surface2}
                stroke={active ? L.color : `${L.color}55`}
                strokeWidth={active ? 2 : 1}
                strokeDasharray={dimmed ? "4,3" : undefined} />
              <text x={p.x + 10} y={p.y + 14} fill={C.muted} fontSize={9.5} fontWeight={700}
                fontFamily="ui-monospace,monospace" letterSpacing={0.3}>{L.id}</text>
              {timeChar && (
                <text x={p.x + SYS_NODE_W - 22} y={p.y + 14} textAnchor="end"
                  fill="#9333ea" fontSize={10} fontWeight={700}
                  fontFamily="ui-monospace,monospace">{timeChar}</text>
              )}
              {/* Status dot — top-right corner */}
              {statusCol && (
                <circle cx={p.x + SYS_NODE_W - 8} cy={p.y + 8} r={3.5}
                  fill={statusCol} stroke={C.surface2} strokeWidth={1}>
                  <title>{STATUS_LABEL[L.status]}</title>
                </circle>
              )}
              <text x={p.x + SYS_NODE_W / 2} y={p.y + 30} textAnchor="middle"
                fill={active ? L.color : C.text} fontSize={12.5} fontWeight={600}>
                {shortLabel}
              </text>
              <text x={p.x + SYS_NODE_W / 2} y={p.y + 44} textAnchor="middle"
                fill={active ? L.color : C.muted} fontSize={10}
                fontFamily="ui-monospace,monospace">
                {L.symbol}
              </text>
            </g>
          );
        })}

        {/* Legend bottom — all indicators */}
        <g transform={`translate(20, ${SVG_H - 18})`}>
          <line x1={0} y1={0} x2={18} y2={0} stroke="#ef4444" strokeWidth={1.1}
            strokeOpacity={0.7} strokeDasharray="4,3" markerEnd="url(#sys-arr-down)" />
          <text x={24} y={4} fill="#ef4444" fontSize={9.5} fontFamily="ui-monospace,monospace">downward causation (constraint)</text>

          <text x={205} y={4} fill="#9333ea" fontSize={9.5} fontFamily="ui-monospace,monospace">t↔ / t→ time character</text>

          <text x={370} y={4} fill={C.muted} fontSize={9.5} fontFamily="ui-monospace,monospace">dashed border: placeholder / abstraction</text>
        </g>
        {/* Status dot legend — second row */}
        <g transform={`translate(20, ${SVG_H - 4})`}>
          {[
            { k: "consensus",      x: 0   },
            { k: "atlas-position", x: 105 },
            { k: "contested",      x: 220 },
            { k: "placeholder",    x: 320 },
          ].map(({ k, x }) => (
            <g key={k} transform={`translate(${x}, 0)`}>
              <circle cx={4} cy={0} r={3.5} fill={STATUS_COLOR[k]} />
              <text x={12} y={3.5} fill={STATUS_COLOR[k]} fontSize={9} fontFamily="ui-monospace,monospace" letterSpacing={0.3}>
                {STATUS_LABEL[k]}
              </text>
            </g>
          ))}
        </g>
      </svg>

      <div style={{ fontSize: 10.5, color: C.muted, fontStyle: "italic", textAlign: "center", marginTop: 4, lineHeight: 1.4 }}>
        Tap any level to expand it in the cards below. Status dots: green/amber/red/grey per the badge legend.
      </div>
    </div>
  );
}

// ─── SYSTEM TYPES — SUBTAB VIEWS ─────────────────────────────────────────────
// Five framings of "what is a system" to compare side-by-side.
// The main spine (L0–L8 built from Distinction + Asymmetry) is one. The other
// four carve up systemhood with genuinely different primitives.

const SYS_VIEWS = [
  { id: "spine",       label: "Spine (L0–L8)",    short: "SPINE",       color: C.sr,  who: "Ladyman, Ross, Shannon, Hoel, Friston",        school: "Structural Realism + Information Theory" },
  { id: "enactive",    label: "Enactivism",        short: "ENACTIVE",    color: C.e4,  who: "Maturana, Varela, Thompson, Di Paolo",         school: "Enactivism / Autopoiesis / 4E Cognition" },
  { id: "cybernetic",  label: "Cybernetics",       short: "CYBERNETIC",  color: C.cyb, who: "Wiener, Ashby, von Foerster, Beer, Bateson",   school: "Cybernetics / Second-Order Cybernetics" },
  { id: "process",     label: "Process",           short: "PROCESS",     color: C.pro, who: "Whitehead, Bergson, Dupré, Nicholson, Seibt",  school: "Process Philosophy / Process Biology" },
  { id: "fep",         label: "Active Inference",  short: "FEP",         color: C.aif, who: "Friston, Parr, Pezzulo, Da Costa",             school: "Active Inference / Free Energy Principle" },
  { id: "constructor", label: "Constructor",       short: "CONSTRUCTOR", color: C.con, who: "Deutsch, Marletto, Vedral",                    school: "Constructor Theory" },
];

const ALT_FRAMEWORKS = {
  enactive: {
    era: "1972 (Maturana–Varela 'Autopoiesis and Cognition') → present (Di Paolo, Thompson, De Jaegher)",
    claim: "Systems are not levels of being to be observed. They are autopoietic unities that produce themselves and bring forth their own world through sense-making coupling with their environment. There is no observer-independent ladder.",
    primitives: [
      { name: "Operational closure", desc: "A network of processes whose products are precisely the components and processes that constitute the network. The system produces itself, including the boundary that distinguishes self from environment." },
      { name: "Sense-making", desc: "Cognition is not internal representation but enaction — bringing forth a world of meaning through embodied action. Significance is constituted by activity, not retrieved from a pre-given world." },
      { name: "Structural coupling", desc: "History of mutual perturbations between system and milieu, without representational mediation. The world a system inhabits is the world it can perturb and be perturbed by." },
    ],
    systemhood: "An autopoietic unity — a network of component-producing processes that maintains and distinguishes itself from its environment. The system creates its own boundary; it is not bounded externally by an observer's coarse-graining.",
    hierarchy: "Nested closures rather than stacked levels. Cellular autopoiesis instantiates the same closure logic later instantiated by multicellular, then cognitive, then social autopoiesis — same form at higher complexity. No L0/L1 substrate: distinction co-emerges with the system that distinguishes; there is no pre-distinction stratum.",
    levels: [
      {
        id: "AE-Cell", label: "Cellular autopoiesis", symbol: "self-producing membrane",
        tagline: "The minimal autopoietic unity — Maturana-Varela's foundational case.",
        detail: `A living cell is a network of molecular processes (enzymatic transformations, membrane synthesis, metabolic regulation) whose products are exactly the components and processes that constitute the network. The cell makes itself, including the membrane that distinguishes self from environment.

The defining structural fact: organizational closure (the network of production loops on itself) combined with thermodynamic openness (matter and energy flow through). These are not separable: closure without openness runs down; openness without closure has no self to maintain.

The boundary is not externally imposed — the membrane is produced by the network the membrane bounds. This circularity is precisely what makes autopoiesis distinct from mere homeostasis. A thermostat is regulated externally; a cell regulates itself by producing what does the regulating.`,
        spineAnalog: "L4-open (boundary exchange) + L5 (self-modification) treated as a single inseparable phenomenon. The Spine cleaves what enactivism unifies.",
        examples: "Bacterium, eukaryotic cell, minimal protocell models (Luisi, Szostak)",
      },
      {
        id: "AE-Org", label: "Organism / animal life", symbol: "nested autopoiesis",
        tagline: "Second-order autopoiesis — components are themselves autopoietic.",
        detail: `An organism is autopoiesis at a higher order. The components are themselves autopoietic (cells), and their network of interaction constitutes a second-order autopoietic unity that produces and maintains itself by producing and maintaining its cellular components.

This is not merely "more cells." Multicellular autopoiesis includes morphogenesis (developing structure), homeostasis across organ systems, immune self-recognition, and metabolic integration that no single cell exhibits. The same closure logic operates at a different scale.

Di Paolo's adaptivity (2005): an organism does not just maintain itself; it actively regulates its relation to environmental conditions to favor continued viability. Adaptivity is autopoiesis with sensitivity to graded violations of viability constraints — the bridge from cellular life to cognition.`,
        spineAnalog: "L5 (adaptive) — but enactivism rejects the framing that adaptation requires irreversibility + emergence + openness as separate ingredients. Adaptation just is autopoiesis under perturbation.",
        examples: "All multicellular organisms; Dictyostelium social amoeba (autopoiesis at two nested orders); biofilms as borderline cases",
      },
      {
        id: "AE-Cog", label: "Cognitive sense-making", symbol: "mind in life",
        tagline: "Cognition is not added on top of life — it is what life does, examined closely.",
        detail: `Thompson's "mind in life" thesis (2007): cognition is continuous with life itself. Wherever there is autopoiesis with adaptive regulation of coupling, there is sense-making — the production of meaning through embodied action.

This collapses the Spine's L6 ↔ L5 boundary. There is no point at which "cognitive systems" become a new category; cognition is a feature of all autopoietic systems with sufficient adaptive regulation. A bacterium following a chemical gradient is doing sense-making — it brings forth a meaningful (food/poison) world through its activity.

The radical implication: representation is not the foundation of cognition. Cognitive systems do not contain internal models of an externally-given world. They enact a world through structural coupling. This is the core disagreement with the Spine's representationalist L6.`,
        spineAnalog: "L6 — but enactivism denies L6 is added to L5. The Spine's representationalist framing of cognition is precisely what radical enactivism rejects.",
        examples: "Bacterial chemotaxis, octopus distributed cognition, plant phototropism (Calvo), embodied human cognition (Gibson, Noë, Di Paolo)",
      },
    ],
    bridgeToSpine: [
      { their: "Operational closure", spine: "L4-open + L5 (combined, not separable)", note: "The Spine cleaves a single phenomenon into 'boundary exchange' and 'self-modification.'" },
      { their: "Sense-making", spine: "Spans L5–L6 (foundational, not derived)", note: "Cognition is co-emergent with life, not added on at L6." },
      { their: "Structural coupling", spine: "Replaces L4-open's external 'boundary'", note: "The boundary is co-constituted by system and environment, not externally given." },
      { their: "Nested autopoiesis", spine: "Replaces L0–L8 ladder", note: "Same closure logic recurs at every scale; not new ingredients per level." },
      { their: "No view-from-nowhere", spine: "Contradicts the Spine's structural-realist commitment", note: "Levels are observer-co-constituted; an observer-independent ladder is impossible in principle." },
    ],
    caveats: [
      { color: "#fbbf24", title: "Internal split: radical vs moderate enactivism", text: "Hutto & Myin's REC (Radical Enactive Cognition, 2013) denies all internal content. Thompson and Di Paolo allow weaker forms of representation in higher cognition. The school is not unified on its deepest claim." },
      { color: "#ef4444", title: "Coupling-constitution fallacy", text: "Adams & Aizawa (2008) argue enactivism conflates causal coupling with constitutive part-of-cognition. Brain, body, and environment are coupled — but that does not make all of them parts of the cognitive system." },
      { color: "#fbbf24", title: "Scale-up problem", text: "Cellular autopoiesis has a rigorous mathematical definition (Maturana-Varela 1980). 'Social autopoiesis' (Luhmann) and 'cognitive autopoiesis' are looser uses that critics (Bechtel, Bourgine, Stewart) argue stretch the original concept past its useful range." },
      { color: "#ef4444", title: "The hard problem reappears", text: "Even granted enaction's account of behavior, the hard problem of consciousness is not solved. Thompson concedes this; some enactivists (Frankish, Dennett-style) sidestep by denying phenomenal consciousness exists." },
      { color: "#fbbf24", title: "Lack of formal apparatus", text: "Compared to FEP or Constructor Theory, enactivism is mostly qualitative. Operational closure has a formal definition; adaptive regulation and sense-making remain prose. Critics ask: where are the equations? Defenders point to enactive robotics (Pfeifer, Beer) but the formal core remains thin." },
      { color: "#94a3b8", title: "Disputed predictive content", text: "Critics ask: what does enactivism predict that representationalism does not? Defenders point to embodied robotics, dynamical-systems cognitive models, and developmental psychology. The empirical track record is real but contested." },
      { color: "#94a3b8", title: "Risk of co-option", text: "Many cognitive scientists now describe their work as 'embodied/embedded/extended' without committing to the deeper enactivist anti-representationalism. The label has spread faster than the substantive thesis." },
    ],
    whenWins: "Reach for enactivism when the question is: how does meaning arise without a pre-given world? Strong fit for embodied cognitive science, developmental psychology, robotics where the agent must construct its world from interaction, and philosophy-of-mind questions about the constitution of experience. Weak fit for physics, statistical mechanics, or any question where observer-independent structure matters.",
    compare: [
      { q: "What is primitive?",          spine: "Distinction + Asymmetry",                  this: "Closure + coupling + sense-making" },
      { q: "What makes something a system?", spine: "Occupies a level via added ingredient", this: "Maintains autopoietic closure over time" },
      { q: "How does hierarchy work?",    spine: "Linear ladder, each level adds one thing",  this: "Nested self-similar closures — recursion, not addition" },
      { q: "Where does cognition enter?", spine: "L6 — derived from L5 adaptation",          this: "Foundational — co-emergent with life itself (mind in life thesis)" },
      { q: "Downward causation?",         spine: "Constraint-imposition (Juarrero/Hoel/Ellis)", this: "Circular causality — whole and parts co-constitute, no priority" },
    ],
    tension: "Rejects the view-from-nowhere. The atlas's spine implicitly treats levels as third-person observable categories — a god's-eye ladder. Enactivists hold that levels are co-constituted by the observer-system that picks them out; there is no observer-independent hierarchy. This collapses L0 entirely (no pre-distinction substrate exists), and inverts L7 from 'derived' to 'foundational' — sense-making is primary, not what falls out of sufficient asymmetric complexity. The atlas's structural-realist commitment cannot be made compatible with strong enactivism without giving up the ladder.",
  },

  cybernetic: {
    era: "1948 (Wiener 'Cybernetics') → 1956 (Ashby 'Introduction to Cybernetics') → 1970s (von Foerster, Maturana — second-order) → present (control theory, systems thinking, Luhmann)",
    claim: "Systems are stable feedback loops. The structural primitive isn't being but regulation — whatever maintains a variable against disturbance is a system. Second-order cybernetics extends this to include the observer in the loop.",
    primitives: [
      { name: "Feedback", desc: "Closed causal loop in which output influences input. Negative feedback stabilizes; positive feedback amplifies. Causation is circular, not linear." },
      { name: "Requisite variety", desc: "Ashby's Law: a regulator must have at least as much variety as the system it regulates. Only variety absorbs variety — the foundational law of cybernetic systems." },
      { name: "Observer-inclusion (second-order)", desc: "The observer is part of the system observed. Von Foerster: 'objectivity is the delusion that observation can be done without an observer.'" },
    ],
    systemhood: "A stable feedback loop maintaining some variable within bounds. Boundaries are defined by what is and isn't part of the regulatory loop. A thermostat alone is not a system; a thermostat + room + heat source + observer all are.",
    hierarchy: "Control hierarchies — Beer's Viable System Model has 5 nested systems (operations, coordination, control, intelligence, policy), each absorbing the variety the level below cannot handle. Higher levels regulate variety, not 'add ingredients.' Variety, not being, is the currency of hierarchy.",
    levels: [
      {
        id: "CY-FB", label: "Negative feedback (homeostat)", symbol: "ẋ = -k(x − setpoint)",
        tagline: "The minimal cybernetic system — a single negative-feedback loop.",
        detail: `A homeostat (Ashby 1952) is a device that maintains a variable near a setpoint by sensing deviation and producing a corrective response. The thermostat is the canonical example; the homeostat-as-organism is Ashby's deeper claim: living systems are nothing but vast collections of such loops.

The key structural fact is closure: the output of the regulator feeds back into the variable it regulates. This closure is what makes the system a system. Cut the loop — open the feedback — and you have a controller and a process, but not a cybernetic system.

For the Spine, this is approximately L4-thermo (an irreversibility-driven equilibrium). For cybernetics, the feedback loop is not at any "level" — it is the primitive structure that every system worth the name instantiates.`,
        spineAnalog: "Crosses L4-thermo, L4-open, and L5 — cybernetic systems are not levelable. A thermostat (L4-thermo on the Spine) and a learning agent (L5) are both single-loop or multi-loop regulators.",
        examples: "Thermostat, glucose homeostasis, predator-prey population dynamics, PID controllers",
      },
      {
        id: "CY-1O", label: "First-order cybernetics", symbol: "Observer → System",
        tagline: "Wiener, Ashby: the science of control and communication in animals and machines, observed from outside.",
        detail: `First-order cybernetics treats the system-observer split as natural and unproblematic. The cybernetician stands outside the system, identifies the controlled variable, measures variety, and characterizes the regulator. Ashby's Law (regulator variety ≥ disturbance variety) is its central theorem; the Conant-Ashby theorem (every good regulator of a system must contain a model of that system) is its sharpest consequence.

This is where engineering control theory, operations research, and Wiener-Bigelow-Rosenblueth's "teleological mechanism" sit. It's also where AI as control problem (RL = optimal control + uncertainty) traces its lineage.

The Conant-Ashby result is structurally important for this atlas: every regulator at the Spine's L4 must, on this reading, contain at L4 itself a model of what it regulates — collapsing the L6 ↔ L4 distinction that the Spine carefully draws.`,
        spineAnalog: "Spine treats modeling (L6) as added to dynamics (L4-complex). Conant-Ashby denies this clean separation — any reliable regulator is already a modeler.",
        examples: "Industrial process control, autopilot, Kalman filter, classical RL (TD-learning), Wiener's anti-aircraft predictor",
      },
      {
        id: "CY-2O", label: "Second-order cybernetics", symbol: "Observer ∈ System",
        tagline: "von Foerster, Maturana: the cybernetics of observing systems.",
        detail: `In the 1970s, von Foerster, Maturana, Mead, and others argued that first-order cybernetics quietly assumes a privileged outside observer — an assumption no cybernetician can claim coherently, since the observer is themselves a feedback system. Second-order cybernetics folds the observer back into the loop.

This is the cybernetics of self-reference, of how observers construct observations, of how distinctions are drawn rather than discovered. Von Foerster's "objectivity is a subject's delusion": there is no description without a describer; the describer is part of what's described.

This is the move that exits engineering and enters philosophy. It is also the move that has been criticized for sliding toward solipsism — if every observation is the observer's construction, on what does cybernetics stand? Maturana's response: structural coupling (the basis for enactivism). Luhmann's response: sociology of distinction-drawing systems. The disagreement continues.`,
        spineAnalog: "Directly opposes the Spine's structural-realist commitment to observer-independent levels. There are no levels-from-nowhere in second-order cybernetics.",
        examples: "Maturana-Varela autopoiesis (1972 — bridges to enactivism), Luhmann's social systems theory, von Foerster's Heinz von Foerster Society work, family therapy (Bateson)",
      },
      {
        id: "CY-VSM", label: "Viable System Model (Beer)", symbol: "S1 + S2 + S3 + S4 + S5",
        tagline: "Five nested control systems make a viable organism, organization, or institution.",
        detail: `Stafford Beer's Viable System Model (1972, 1979) identifies five nested cybernetic subsystems any system must have to remain viable in a complex environment:

• **S1 — Operations:** the primary value-producing activities (production cells, organs, divisions)
• **S2 — Coordination:** damping oscillations between S1 units (schedulers, autonomic nervous system)
• **S3 — Control:** synergy and resource allocation across S1 (executive management, brain stem regulation)
• **S4 — Intelligence:** environmental scanning and adaptation planning (R&D, strategic perception)
• **S5 — Policy:** identity and constitution (board, prefrontal self-model)

Each Si regulates the variety the Si-1 level cannot handle. Hierarchy is not "more being" but "more variety to absorb." VSM was actually implemented (Allende's Cybersyn, 1971-73) before being cut short by the Pinochet coup.`,
        spineAnalog: "VSM is a meta-architecture that crosscuts L5 (S1-S3 operations and coordination) and L6-L7 (S4-S5 modeling and self-modeling). It is a different cut.",
        examples: "Cybersyn (Chile, 1971-73), human autonomic + cognitive nervous systems, biological cell as VSM (Beer), corporate organizational design",
      },
    ],
    bridgeToSpine: [
      { their: "Negative feedback loops",   spine: "Present at every Spine level worth calling a system (L4+)", note: "The Spine treats feedback as something that emerges at L5+; cybernetics treats it as primitive." },
      { their: "Ashby's Law (requisite variety)", spine: "No Spine equivalent — variety isn't in the IT anchor as Ashby uses it", note: "Variety ≈ entropy of state space, but Ashby's regulatory framing isn't part of the Spine's vocabulary." },
      { their: "Conant-Ashby theorem",      spine: "Collapses L4 ↔ L6 distinction", note: "Every regulator is already a modeler — modeling isn't an extra ingredient added at L6." },
      { their: "Second-order observer-inclusion", spine: "Contradicts SR's observer-independence", note: "Levels are observer-constructed, not observer-independent — direct rejection of OSR." },
      { their: "VSM's 5 nested systems",    spine: "Crosscuts L5–L7 with a different (functional) cut", note: "Beer's hierarchy is functional (what variety each absorbs); the Spine's is ontological (what ingredient each adds)." },
    ],
    caveats: [
      { color: "#ef4444", title: "Goal-setting regress", text: "Cybernetic regulation presupposes a setpoint — but who sets it? A regulator regulating a setpoint requires a higher regulator setting that setpoint, ad infinitum. Ashby acknowledged this; cybernetics has no foundational answer." },
      { color: "#fbbf24", title: "Ashby's Law trivializes in the data era", text: "When a deep network has 10^11 parameters, the 'variety' on hand outstrips any realistic disturbance. Ashby's Law becomes nearly content-free for modern ML systems — the constraint it expresses is rarely the binding one." },
      { color: "#ef4444", title: "Practical management failures", text: "Cybersyn (Allende's Chile) was destroyed politically before maturity, but the broader 'managerial cybernetics' research program (RAND, Forrester, Beer) largely faded after the 1980s. Its grand ambition (govern complex society through measured feedback) did not survive contact with messy reality." },
      { color: "#fbbf24", title: "Second-order drift toward solipsism", text: "Von Foerster's late work (1990s) pushed toward 'reality is a construct.' Critics (Hayles, Pickering) argue this dissolves cybernetics' ability to discriminate good from bad models of physical systems." },
      { color: "#ef4444", title: "Doesn't handle thermodynamic asymmetry", text: "Wiener's 'entropy' is informational (uncertainty); Boltzmann's is thermodynamic. The two coincide formally but not in their physical content. Cybernetics is silent about the L4-thermo arrow of time, treating all dissipation as variety to be absorbed." },
      { color: "#fbbf24", title: "Observer-relativity undermines self-grounding", text: "If system boundaries are observer-drawn (second-order), then cybernetics itself is one possible observation among many — a stance, not a science. This is uncomfortable for a research program with engineering ambitions." },
    ],
    whenWins: "Reach for cybernetics when the question is: how does this system maintain itself against disturbance, and what would it take to control or improve it? Strong fit for engineering systems, organizational design, biological regulation, RL/optimal control, and any setting where the regulatory loop is the unit of analysis. Weak fit for ontological questions about what kinds of things exist.",
    compare: [
      { q: "What is primitive?",          spine: "Distinction + Asymmetry",                  this: "Feedback + variety + (2nd order) observer" },
      { q: "What makes something a system?", spine: "Occupies a level",                      this: "Maintains a stable feedback loop against disturbance" },
      { q: "How does hierarchy work?",    spine: "Each level adds an ingredient",            this: "Each level absorbs more variety than the one below (VSM)" },
      { q: "What is law-like?",           spine: "Physical/dynamical laws + measure theory", this: "Ashby's Law (requisite variety) + Conant-Ashby (regulator models regulated)" },
      { q: "Downward causation?",         spine: "Constraint-imposition",                    this: "Higher-level controllers modulate lower-level variety — by design" },
    ],
    tension: "Cybernetics has no 'structureless substrate.' Feedback is primary, not derived. The spine treats feedback as something that emerges at L5+; cyberneticians treat it as present at every level worth calling a system (even a thermostat in a room is a control loop). Second-order cybernetics presses a sharper tension: observer-independence is impossible. The spine's structural-realist commitment to observer-independent levels is precisely what second-order cybernetics rejects. The Conant-Ashby theorem (any good regulator of a system must contain a model of that system) collapses the L6 ↔ L4 distinction the spine carefully draws — every controller is already a modeler.",
  },

  process: {
    era: "1907 (Bergson 'Creative Evolution') → 1929 (Whitehead 'Process and Reality') → present (Dupré 'Processes of Life' 2012, Nicholson-Dupré 'Everything Flows' 2018, Seibt 'Process Theories' 2003)",
    claim: "Process is fundamental; 'things' are stabilized processes. Static structure is an abstraction from a more primary becoming. Heraclitus over Parmenides, applied with mathematical and biological seriousness.",
    primitives: [
      { name: "Actual occasions / events", desc: "Whitehead: the basic unit of reality is an event of becoming, not an enduring substance. The world is built of occasions, not things. Each occasion is an atomic moment of experience-and-becoming." },
      { name: "Prehension", desc: "How an occasion 'feels' its predecessors — incorporates the past into its own becoming. Causation is prehensive uptake, not external push. Each new occasion arises by prehending all that has gone before." },
      { name: "Concrescence", desc: "The process by which the many become one and are increased by one. Each occasion synthesizes its inheritance into a novel unity, then perishes into the next. Becoming is creative, not deterministic." },
    ],
    systemhood: "A nexus of occasions — a stable pattern of becoming with a characteristic order. Not a substance with properties but a society of events. Organisms, atoms, and electrons are equally 'occasions of experience' — process all the way down.",
    hierarchy: "Not a hierarchy of being but of temporal nestedness. Microsecond occasions nested within longer temporal patterns. 'Things' are how processes appear when viewed at slower-than-process timescales. Atoms are slow patterns; organisms slower; institutions slower still.",
    levels: [
      {
        id: "PR-AO", label: "Actual occasions", symbol: "atom of becoming",
        tagline: "Whitehead's minimal unit — a quantum of becoming, not of being.",
        detail: `For Whitehead, the basic unit of reality is the actual occasion: an atomic event in which the past is prehended (felt, taken in), concrescence occurs (the many become one), and the new occasion arrives at satisfaction and perishes into objective immortality (data for future occasions).

An actual occasion is not a thing — it has no enduring substance. It is a momentary act of becoming. The world is a vast plurality of such occasions, related to one another by prehension. What we call "objects" are nexus — stable patterns of occasion-to-occasion inheritance.

This is the deepest Whiteheadian commitment: there is nothing that simply IS; there is only what becomes. Substance metaphysics (a thing is what it is regardless of what it does) is replaced wholesale.`,
        spineAnalog: "No clean analog. The Spine starts with states (L1) and their changes (L3); Whitehead's occasion is neither — it is the unit of change itself, prior to any state-vs-change split.",
        examples: "A photon absorption event, a neural firing, a moment of conscious experience, a quantum measurement (loosely)",
      },
      {
        id: "PR-MOL", label: "Molecular / chemical processes", symbol: "ongoing reactions",
        tagline: "Atoms and molecules as stabilized patterns of becoming.",
        detail: `On the process reading, an atom is not an enduring thing but a stable pattern in which similar occasions recur with characteristic statistical regularity. Quantum field theory is hospitable to this: there are no enduring particles, only excitations of fields, and the "identity" of a particle is just the regularity of its mode of excitation.

Dupré and Nicholson (2018) push this in biology: cells, organisms, ecosystems are not collections of static parts but living processes — patterns of metabolism, repair, replacement, and reproduction. A cell's "components" are constantly being replaced; what persists is the process pattern, not the substance.

This dissolves the Spine's L1 (distinguished set) as a fundamental category. There is no enduring "particle" or "molecule" to be set-membership-identified; there are only ongoing processes that appear particle-like at slow observational scales.`,
        spineAnalog: "Re-reads L1 (distinguished set) and L2 (structured graph) as temporal slices through ongoing molecular processes. Nothing simply is a particle; particles are slow becomings.",
        examples: "Catalytic cycles, autocatalytic sets (Kauffman), metabolic networks, BZ chemical oscillators",
      },
      {
        id: "PR-BIO", label: "Biological processes (Dupré)", symbol: "life-history as process",
        tagline: "Dupré: organisms are life-history processes, not enduring substances.",
        detail: `Dupré's process biology (2012, 2018) makes the Whiteheadian core empirically tractable. Take an organism: it is constantly replacing its constituents (cells turn over, atoms cycle, the body of "you" five years ago contains almost no matter in common with the body now). What persists is the life-history process — the pattern of becoming-this-organism.

This reframes biological identity: a species is not a class of similar organisms but a slow process of population-level becoming; an individual is not a substance but a metabolic-developmental process; a gene is not a thing but a stable replication-pattern.

The move is empirically powerful — it dissolves several long-standing puzzles (species individuality, gene identity, the metabolic-vs-replication divide) into a single process-ontological framework. It is also where most contemporary process philosophy actually lives.`,
        spineAnalog: "Re-reads L5 (adaptive systems) and L4-open (open systems) as inseparable aspects of biological process. Adaptive openness is what an organism IS, not a feature it has.",
        examples: "Organisms across their life history, ecological successions, species as historical lineages, immune memory as ongoing process",
      },
      {
        id: "PR-SOC", label: "Social and institutional processes", symbol: "practice over substance",
        tagline: "Institutions, cultures, and selves as stable patterns of practice.",
        detail: `At social scales, process philosophy reframes institutions, cultures, and selves as stable patterns of practice rather than enduring entities. A university is not the buildings or the official charter — it is the ongoing process of teaching, researching, credentialing that the buildings and charter coordinate. Stop the practices and the institution evaporates regardless of what the buildings hold.

Similarly the self: not an enduring substance but a process of self-organization across time. Whitehead, Mead, Bakhtin, and later social-process theorists (Rorty, Latour as critic, Abbott as practitioner) develop this. It connects naturally to second-order cybernetics (Luhmann's social systems as processes of distinction-drawing) and to enactivism's nested closure.

The philosophical payoff: identity (personal, institutional, national) becomes diachronic by default, not synchronic-with-temporal-extension. We are processes that re-occur with sufficient regularity to be re-cognized.`,
        spineAnalog: "Re-reads L8 (social systems) and L7 (reflexive systems) as scales of ongoing practice. Identity is re-occurrence of pattern, not enduring substance — pushing back on the Spine's reflexive-individual-first framing.",
        examples: "Universities, religions, professional practices, the self as ongoing autobiographical process, languages as evolving usage-patterns",
      },
    ],
    bridgeToSpine: [
      { their: "Actual occasions",          spine: "No analog — Spine starts with states + changes; Whitehead starts with becoming", note: "Process denies the state/change split is fundamental." },
      { their: "Prehension (causation)",    spine: "Replaces Pearl's do-calculus at L4+", note: "Causation is uptake of the past by the present, not external intervention." },
      { their: "Stabilized patterns",       spine: "Re-reads L1 + L2 as temporal slices", note: "L1 (distinguished set) and L2 (graph) are abstractions from ongoing process — the slice is not the process." },
      { their: "Life-history process",      spine: "Re-reads L5 (adaptive) as inseparable from L4-open", note: "Dupré: adaptation isn't ingredient-added; it is what biological process is." },
      { their: "Practice over substance",   spine: "Re-reads L7 + L8 as scales of becoming", note: "Identity is re-occurrence of pattern, not enduring substance." },
    ],
    caveats: [
      { color: "#fbbf24", title: "Whitehead's opacity", text: "Whitehead's terminology (prehension, concrescence, occasion, nexus, eternal objects) is notoriously dense; even sympathetic readers (Hartshorne, Cobb, Griffin) disagree about basic exegesis. Most contemporary process work simplifies or selectively borrows rather than using the full apparatus." },
      { color: "#ef4444", title: "Panpsychist vs naturalistic split", text: "Whitehead held that every actual occasion has subjective immediacy — a panpsychist commitment. Dupré, Nicholson, and most contemporary process biologists reject panpsychism but retain the process ontology. The split fragments the school." },
      { color: "#ef4444", title: "Stability problem", text: "If everything is becoming, why does anything persist? The answer (re-occurrence of pattern) sounds like structuralism in disguise. Critics (Lowe, Mumford) argue process philosophy needs a stability-explainer that ends up looking like substance." },
      { color: "#fbbf24", title: "Causal efficacy of perishing occasions", text: "A 'perished' occasion (Whitehead) cannot push another — yet causation requires that prior occasions affect later ones. Whitehead's solution (objective immortality + prehension) is metaphysically loaded and not widely accepted outside dedicated Whitehead scholarship." },
      { color: "#ef4444", title: "Dupré narrows the scope", text: "Contemporary biological process philosophy (Dupré-Nicholson) is empirically strong but limited to biology. It loses Whitehead's universal scope and becomes a regional thesis. Critics ask: if process is only true of biology, what's the metaphysical claim?" },
      { color: "#fbbf24", title: "Lack of formal apparatus", text: "Compared to FEP, Constructor Theory, or even Spine-style information theory, process philosophy is sparse in equations. There are exceptions (some category-theoretic work on processes — Coecke), but the dominant mode is qualitative." },
      { color: "#94a3b8", title: "Compatibility with physics is unclear", text: "QFT is process-friendly; classical mechanics and standard general relativity are substance-friendly (objects with worldlines). Whether process philosophy can be made fully consistent with current best physics remains open." },
    ],
    whenWins: "Reach for process when the question is: what persists, and why, in a world where everything changes? Strong fit for biology (organisms as life-history processes), institutions and history, identity over time, and quantum-field-theoretic intuitions. Weak fit for static structural analysis (mathematics, formal computer science, equilibrium physics).",
    compare: [
      { q: "What is primitive?",          spine: "Distinction + Asymmetry",                  this: "Becoming + prehension + concrescence" },
      { q: "What makes something a system?", spine: "Occupies a level",                      this: "Stable nexus of occasions with characteristic order" },
      { q: "Is static structure real?",   spine: "L2 marked 'modeling abstraction'",         this: "ALL static structure is abstraction — even L1 is a temporal slice" },
      { q: "What is time?",               spine: "Parameter at L3, arrow at L4",             this: "The primary mode of being; 'atemporal' is incoherent" },
      { q: "Identity?",                   spine: "Derived from pattern of difference (SR)",   this: "Re-occurrence of pattern across occasions; nothing endures unchanged" },
    ],
    tension: "Process philosophy denies the spine's structural-realist resolution that 'structure and process are duals.' For process philosophers (Dupré in biology, Nicholson on organisms, Seibt in metaphysics), things are abstractions from processes, not vice versa. Treating L2 as a real category — even when marked 'modeling abstraction' — mistakes the projection for the projector. The deeper challenge: structure-talk hides the temporal becoming that makes structure possible. Whitehead's actual occasion has no purely 'structural' reading. The spine's atemporal levels (L0, L1, L2) are exactly the abstractions process philosophy says we must give up.",
  },

  fep: {
    era: "2006 (Friston 'A free energy principle for the brain') → 2012+ (extension to all self-organizing systems) → 2019+ (FEP as mathematical principle of stationary random dynamical systems) → 2022 (Parr-Pezzulo-Friston textbook)",
    claim: "Anything that exists must minimize variational free energy (an upper bound on surprisal) to persist. A single mathematical principle unifies physics, biology, and cognition. Systemhood is reducible to the maintenance of a Markov blanket.",
    primitives: [
      { name: "Variational free energy F[q]", desc: "F = D_KL(q(s)‖p(s,o)) — an upper bound on surprisal -log p(o). Minimizing F is what all persistent systems implicitly do." },
      { name: "Markov blanket", desc: "A set of variables (sensory + active states) that statistically separates internal from external states. Internal and external are conditionally independent given the blanket." },
      { name: "Generative model", desc: "An organism's (implicit or explicit) model of how its observations are caused. Action and perception jointly minimize prediction error against this model." },
    ],
    systemhood: "Anything that maintains a Markov blanket over time. A set of variables qualifies as a system iff there exists a blanket separating it from its surround such that the blanket statistics persist. Falls naturally out of stationarity in random dynamical systems (Friston 2019) — but the formal claim is contested.",
    hierarchy: "Hierarchical generative models — higher levels encode predictions about lower-level dynamics; lower-level prediction errors flow upward to update higher beliefs. Not levels of being but levels of inference. Cortical microcircuits, perception, action, planning, and self-modeling are the same algorithm at different temporal scales.",
    levels: [
      {
        id: "FE-MB", label: "Markov blanket (basic systemhood)", symbol: "b = {s, a}",
        tagline: "The minimal FEP criterion: a statistical boundary that persists.",
        detail: `For a set of variables to be a "system" in FEP, there must exist a Markov blanket — a subset (sensory + active states) such that internal and external states are conditionally independent given the blanket. The blanket is what makes "internal" and "external" well-defined.

Friston's 2019 claim: in any stationary random dynamical system, Markov blankets emerge naturally as the structure that supports stationarity. This is what is meant by "FEP applies to anything that exists" — to persist as a recognizable thing IS to maintain a blanket.

The claim is mathematically suggestive but contested. Aguilera et al. (2022, PNAS) showed that Markov blankets are non-unique or non-existent in many realistic stochastic systems. Bruineberg et al. (2022) argue blankets are inferential tools observers apply to systems, not features intrinsic to the systems themselves. The status of FE-MB as the foundation of FEP is open.`,
        spineAnalog: "Roughly L4-open's 'boundary' — but FEP makes this the criterion of systemhood, while the Spine treats it as one ingredient among others.",
        examples: "A cell (membrane = sensory+active states), an organism's body, a brain (skull + sensory surfaces), arguably a transformer at inference",
      },
      {
        id: "FE-HM", label: "Homeostatic regulation", symbol: "minimize sensory variance",
        tagline: "Variance-minimizing systems — keep observations within survivable bounds.",
        detail: `The simplest non-trivial FEP system minimizes the variance of its sensory states against an internal setpoint. A thermostat-organism reads temperature, acts on temperature, and over time maintains low sensory variance. This is variational inference at its most basic: the internal "model" assumes the world is near setpoint; the action minimizes prediction error.

This is where FEP starts to look like a re-description of cybernetic homeostasis — and critics (Andrews 2021) argue it IS just homeostasis with extra notation. The defense: FEP unifies many homeostat-like systems under one optimization (free energy), which makes their similarity computationally manifest in a way ad-hoc descriptions don't.

For the Spine, this is L4-thermo + L4-open with explicit setpoint maintenance — what cybernetics calls a first-order regulator.`,
        spineAnalog: "L4-thermo + L4-open. The Spine cleaves thermo from open; FEP unifies them as the same homeostatic principle in different operational regimes.",
        examples: "Thermoregulation in mammals, osmoregulation in cells, simple navigation agents in RL",
      },
      {
        id: "FE-AI", label: "Active inference", symbol: "minimize expected F",
        tagline: "Action and perception jointly minimize expected free energy.",
        detail: `Active inference extends FEP from passive prediction to action selection. An agent picks the policy (sequence of actions) that minimizes expected free energy: an objective that balances expected prediction error (epistemic value) against expected utility (extrinsic value).

This is where FEP makes contact with decision theory, RL, and behavioral neuroscience. Many phenomena from animal foraging to human exploration-exploitation tradeoffs have been described as active inference. The framework also predicts curiosity (epistemic value drives exploration of uncertain states) — addressing one version of the dark-room critique.

But: Biehl-Pollock-Kanai (2021) showed formally that expected free energy is NOT derivable from the FEP itself; it must be added as a separate objective. This weakens the unification claim: FEP-the-principle doesn't entail active-inference-the-algorithm.`,
        spineAnalog: "L5 (adaptive) extended into L6 (cognitive) via the predictive-processing thesis. FEP collapses what the Spine separates into 'adaptation' and 'modeling.'",
        examples: "Predictive coding in vision (Rao-Ballard 1999), exploration in RL, perceptual psychology of attention, model-based reinforcement learning",
      },
      {
        id: "FE-DH", label: "Deep / temporal hierarchy", symbol: "hierarchical predictive processing",
        tagline: "Stacked generative models at multiple timescales — perception to planning to selfhood.",
        detail: `Mature active inference uses hierarchical generative models: each level encodes predictions about a slower-timescale variable than the level below. At the bottom: rapid sensory predictions (milliseconds). At the top: slow self-narrative and goal structures (years). Prediction errors flow up; precision-weighted predictions flow down.

For FEP enthusiasts (Friston, Pezzulo, Parr), this is the unified algorithmic substrate of cognition — perception, action, attention, planning, language, and self-modeling are all instances of hierarchical predictive inference. For the Spine, this collapses L6, L7, and the upper edge of L8 into one mechanism with depth-as-the-only-difference.

The empirical track record is mixed: predictive coding accounts of perception (Rao-Ballard, Friston-Kiebel) are well-supported; predictive coding accounts of action and consciousness are more speculative. Hierarchical active inference is at the research frontier.`,
        spineAnalog: "Compresses L6, L7, and part of L8 into one mechanism — the Spine's level distinctions become depth-of-hierarchy distinctions in FEP.",
        examples: "Predictive coding in cortex, language as hierarchical inference, model-based planning, self-modeling as deep generative inference",
      },
    ],
    bridgeToSpine: [
      { their: "Markov blanket",            spine: "Replaces L4-open's 'boundary' as systemhood criterion", note: "FEP makes blanket-maintenance THE criterion; Spine makes it one ingredient." },
      { their: "Variational free energy",   spine: "Borrowed at L5 as the info quantity, not extended further", note: "Spine uses F[q] at L5 only; FEP claims it explains all levels." },
      { their: "Active inference",          spine: "Crosses L5 + L6 in one mechanism", note: "Spine cleaves adaptation (L5) from modeling (L6); FEP unifies them." },
      { their: "Hierarchical predictive processing", spine: "Compresses L6 + L7 + L8 upper edge into depth-of-inference", note: "Levels become depth-of-generative-model, not kinds of being." },
      { their: "One principle for everything", spine: "Plurality of frameworks per level", note: "FEP claims unification; Spine acknowledges level-specific theory." },
    ],
    caveats: [
      { color: "#ef4444", title: "Andrews 2021: trivial-or-wrong dichotomy", text: "Andrews (Synthese 2021) argues FEP faces a dilemma: either it is trivially true (any persistent system can be re-described as minimizing some free energy, making FEP unfalsifiable) or it makes substantive predictions that are wrong (e.g., agents should minimize sensory variety — but living agents seek out variance)." },
      { color: "#ef4444", title: "Biehl-Pollock-Kanai 2021: expected F doesn't follow from FEP", text: "Formal result (Entropy): the expected-free-energy objective that drives active inference cannot be derived from the FEP itself. It must be added as a separate normative claim. This weakens FEP's unification claim — FEP-the-principle does not entail active-inference-the-algorithm." },
      { color: "#ef4444", title: "Aguilera et al. 2022: Markov blankets non-unique", text: "Aguilera, Millidge, Tschantz, Buckley (PNAS): in many stochastic systems, Markov blankets are non-unique, time-varying, or non-existent. The blanket is not a structural feature of a system but an observer-chosen partition." },
      { color: "#fbbf24", title: "Bruineberg et al. 2022: instrumentalist reading", text: "Bruineberg, Dolega, Dewhurst, Baltieri (Synthese 2022): Markov blankets in FEP are tools we apply to systems, not features the systems intrinsically have. If accepted, FEP becomes a modeling stance rather than a description of reality." },
      { color: "#fbbf24", title: "Dark-room problem", text: "If agents minimize surprise, why don't they sit in dark rooms minimizing all sensory input? Friston's epistemic-value answer is contested as ad hoc — added precisely because the basic FEP predicts the wrong thing." },
      { color: "#ef4444", title: "'Free energy' is a misleading borrow", text: "FEP's F[q] is not thermodynamic free energy — it is a variational bound on negative log evidence (a quantity from statistical inference). Andrews, Biehl, and others argue the terminology has bred unwarranted physical intuitions. They share a name and a structural form; nothing more." },
      { color: "#fbbf24", title: "Reverse engineering, not prediction", text: "FEP shines at explaining post hoc why a known persistent system persists — by re-describing it in FEP terms. Critics ask: where are the novel predictions? Defenders point to specific predictive-coding experimental results, but the FEP-the-meta-principle (vs predictive coding specifically) has thin novel predictive content." },
      { color: "#94a3b8", title: "Friston's exposition is notoriously inaccessible", text: "Even sympathetic readers (Parr, Da Costa) acknowledge Friston's papers are hard to parse. This has slowed scrutiny — many critics report finding it difficult to be sure they understand what they are criticizing, and Friston's responses sometimes appear to shift the formal claim." },
    ],
    whenWins: "Reach for FEP when the question is: how do persistent agents balance perception and action under uncertainty? Strong fit for predictive coding in neuroscience, active perception in robotics, and theoretical unification across perception–action–decision. Weak fit when the system is non-stationary, when Markov blankets are ill-defined, or when the question is metaphysical (what kinds of things exist) rather than algorithmic (how do they self-maintain).",
    compare: [
      { q: "What is primitive?",          spine: "Distinction + Asymmetry",                  this: "Free energy + Markov blanket + generative model" },
      { q: "What makes something a system?", spine: "Occupies a level via added ingredient", this: "Maintains a Markov blanket — one criterion, one principle" },
      { q: "How does hierarchy work?",    spine: "Levels of being (each adds an ingredient)", this: "Levels of inference (each predicts the level below)" },
      { q: "What unifies systems?",       spine: "Shared info-theoretic vocabulary",          this: "All systems minimize free energy — same principle, different generative depth" },
      { q: "Downward causation?",         spine: "Constraint-imposition",                    this: "Top-down precision-weighted predictions modulate lower-level dynamics" },
    ],
    tension: "FEP is a much more committed framework than the spine's plural use of frameworks. It claims ONE principle (free energy minimization) explains everything from particles to societies. This deflates the spine's level distinctions: L4-thermo and L7 differ only in generative-model depth, not in kind. The spine borrows FEP at L5 (variational free energy as the info quantity) but does not extend it as a meta-principle. Strong-FEP critics (Andrews 2021, van Es 2020, Biehl-Pollock-Kanai 2021, Aguilera 2022) argue FEP is either trivially true or substantively wrong. The atlas's stance: FEP is one useful operationalization at L5, not the master key.",
  },

  constructor: {
    era: "2013 (Deutsch 'Constructor Theory of Information', SAA) → 2014–2017 (Marletto-Deutsch 'Constructor Theory of Probability', 'of Life', 'of Thermodynamics') → present (Marletto-Vedral on quantum CT)",
    claim: "Reformulate physics in terms of which physical tasks are possible vs. impossible. Existence, information, and knowledge are downstream of counterfactual task-possibility. Modality is primitive, not derived from dynamics.",
    primitives: [
      { name: "Tasks", desc: "Ordered pairs of input-output states. The basic unit of physics is not 'what happens' but 'what could happen' — a transformation from one specification to another, regardless of whether it actually occurs." },
      { name: "Constructors", desc: "Physical objects that can perform tasks reliably and repeatedly without being consumed. The constructor enters and exits the task with its capacity intact — distinguishing it from one-shot processes." },
      { name: "Counterfactuals as primitive", desc: "Propositions about what is/isn't possible are foundational, not derived. The laws of physics, on Deutsch-Marletto's reading, are laws of impossibility: 'no constructor can perform task T' is the deepest law form." },
    ],
    systemhood: "A substrate is a system iff it supports specific task-transformations under some constructor. Existence is downstream of task-possibility; what something IS is exhausted by what tasks it can support. Identity is a counterfactual signature, not a substantial property.",
    hierarchy: "Not levels of being but classes of tasks. Tasks form a partial order (some require others as prerequisites). Substrates differ in which task-classes they support. Universal constructors (capable of any allowed task) are limiting theoretical cases — Turing machines and (controversially) sufficiently programmable physical systems.",
    levels: [
      {
        id: "CT-TASK", label: "Tasks", symbol: "T = (S_in → S_out)",
        tagline: "Ordered pairs of states. The unit of physics is what could happen, not what does.",
        detail: `Deutsch and Marletto: physics should be reformulated around tasks — input/output state pairs that some constructor could in principle perform. Not "this happened" but "this transformation is possible." This shifts foundational vocabulary from dynamical laws (what evolves) to modal laws (what's allowed).

Examples:
• (cold body, hot body) → (hotter, colder) without work: IMPOSSIBLE (2nd law)
• (qubit |ψ⟩, two copies |ψ⟩|ψ⟩): IMPOSSIBLE in QM (no-cloning theorem)
• (DNA strand, two identical strands): POSSIBLE in cells (with enzymatic machinery as constructor)
• (graphite, diamond): POSSIBLE under high pressure (with appropriate constructor)

A task is not a process — it is a counterfactual specification. The same task may be performable in many different ways, by many different constructors, or by none.`,
        spineAnalog: "No direct Spine analog. The Spine has states (L1) and changes (L3); Constructor Theory has neither as primitive — what's primitive is the counterfactual transformability between specifications.",
        examples: "Computation tasks (Turing machines), thermodynamic tasks (2nd law), quantum information tasks (cloning, deletion, teleportation), biological tasks (DNA replication, protein folding)",
      },
      {
        id: "CT-CON", label: "Constructors", symbol: "C performs T reliably",
        tagline: "Physical objects that reliably enact task transformations without being consumed.",
        detail: `A constructor is what makes a task possible. It enters the world as a substrate that supports specific input-output transformations and emerges unchanged in its capacity to do so again. Examples: a catalyst (chemistry), a copying machine (information), a ribosome (biology), a programmable computer (computation in the abstract).

The key formal property is repeatability — a constructor can be re-used. This distinguishes constructors from one-shot processes. The 2nd law of thermodynamics, on Marletto-Vedral's reformulation, becomes a statement about which constructors cannot exist: there is no reusable constructor that converts heat into work without other compensating changes.

A crucial subtlety: a physical object that performs the task once is not yet a constructor. Constructor-hood is a counterfactual property — the substrate-task pair must hold across many possible runs, including ones that didn't happen.`,
        spineAnalog: "Cuts across L4 (catalysts), L5 (biological replicators), L6 (programmable substrates), and L7 (self-modeling regulators). Constructors don't fit the Spine's ingredient-added levels.",
        examples: "Enzymes, ribosomes, universal Turing machines, programmable computers, photosynthetic machinery in chloroplasts",
      },
      {
        id: "CT-POSS", label: "Possibility / impossibility laws", symbol: "Some T: possible; some T: impossible",
        tagline: "Physics restated as which tasks any constructor can vs. cannot perform.",
        detail: `Constructor-theoretic laws are statements of necessary impossibility. Example: "2nd law: there is no constructor that takes (hot, cold) and produces (work, equally cold) without changing anything else." This is not a probabilistic claim about averages; it is a modal claim about what no constructor anywhere can ever do.

Marletto-Vedral (2014, 2017) derived analogues of the 1st and 2nd laws of thermodynamics in constructor-theoretic terms; Marletto (2015) gave a constructor-theoretic account of life as the requirement for a special kind of error-correcting copying. The reformulation suggests these are not laws about what happens, but about what cannot be made to happen — a deeper modal claim.

What counts as a possibility law is contested. Critics (Hadjichristidis, Vassallo) argue "task" is not specified well enough to ground universal possibility/impossibility claims, especially in QM contexts.`,
        spineAnalog: "Roughly analogous to the Spine's 'physical laws' but framed modally instead of dynamically. The Spine's L3 conservation laws (Noether) are at the actual level; CT's possibility laws are at the modal level — a different stratum.",
        examples: "2nd law (no perpetual motion of 2nd kind), no-cloning (QM), no-deletion (QM), no-broadcasting (QM), Bell inequality violations as possibility constraints",
      },
      {
        id: "CT-INFO", label: "Information as counterfactual", symbol: "I = resilient knowledge",
        tagline: "Information is not Shannon-counted distinctions; it is what resiliently instantiates counterfactuals.",
        detail: `Deutsch-Marletto define information constructor-theoretically: a substrate carries information if it can be reliably replicated AND can causally affect other substrates in ways that depend on its current state. The substrate must support both replication and dependence — what they call the "interoperability" of information media.

Shannon information counts distinguishable states statically. Constructor information requires actual replicability and causal influence — it is an ability, not a quantity. This reframes the Spine's L4-thermo info (Landauer's bit-erasure cost) as a special case of constructor-theoretic limits on copying tasks.

Knowledge, on this reading, is information that resiliently instantiates counterfactuals: it does not just exist but actively reliably specifies how the world could be different under different conditions. This connects to Deutsch's broader epistemology — knowledge as substrate-independent counterfactual structure that resists noise across implementations.`,
        spineAnalog: "Reframes the Spine's IT anchor. The Spine measures distinctions (Shannon); CT measures counterfactual reliability. Different notions of information, both formal, both useful.",
        examples: "Genes (replicate + influence), books and writing (replicate + influence), software (substrate-independent counterfactual structure), beliefs in reasoning agents",
      },
    ],
    bridgeToSpine: [
      { their: "Tasks",                     spine: "No direct analog — Spine has states + changes; CT has counterfactual transformations", note: "CT's primitive (possibility) is upstream of Spine's L1 + L3." },
      { their: "Constructors",              spine: "Crosscut L4 + L5 + L6 + L7", note: "Catalysts (L4), replicators (L5), computers (L6), universal constructors (L7+) are all constructors at different scales." },
      { their: "Possibility laws",          spine: "Replace L3 dynamical laws with modal laws", note: "What the Spine reads as dynamical regularity, CT reads as modal necessity." },
      { their: "Counterfactual information", spine: "Reframes the IT anchor", note: "Spine counts distinctions; CT counts counterfactual reliability — different formal contents under the same word 'information.'" },
      { their: "Universal constructors",    spine: "L7+L8 territory — but framed as 'what tasks does this substrate enable' rather than 'what is the substrate'", note: "Modal capacity, not kind of being." },
    ],
    caveats: [
      { color: "#fbbf24", title: "Early-stage, few empirical predictions", text: "Constructor Theory was published in 2013. Compared to FEP (16+ years and a textbook) or enactivism (50+ years), the empirical track record is thin. The novel testable predictions — beyond reformulations of known thermodynamic results — are few and contested." },
      { color: "#ef4444", title: "Task individuation problem", text: "Critics (Hadjichristidis, Vassallo, Bell) argue 'task' is not well-enough specified to ground universal possibility/impossibility claims. What counts as the same task across different substrates? How fine-grained must the input/output specification be? These foundational questions are open." },
      { color: "#ef4444", title: "Conflation of physical and logical possibility", text: "Constructor Theory speaks of 'possible' tasks. But physical possibility (consistent with laws of physics) and logical possibility (consistent with non-contradiction) are different. Some critics argue CT slides between these without clean separation." },
      { color: "#fbbf24", title: "Universality is unfalsifiable in a useful sense", text: "The 'universality principle' (a universal constructor capable of any allowed task exists) is hard to falsify — what counts as 'all possible tasks' is itself a constructor-theoretic question. Some critics argue this makes the principle vacuous as a physical postulate." },
      { color: "#fbbf24", title: "Relation to ordinary physics unclear", text: "How does Constructor Theory connect to QFT, GR, statistical mechanics? Marletto-Vedral's quantum-CT work is suggestive but not yet integrated with mainstream physics. The reformulation is currently 'physics retold,' not 'new physics derived.'" },
      { color: "#ef4444", title: "Promises more than yet delivered", text: "The grand ambition (re-found physics on counterfactuals) has produced reformulations of thermodynamics and information theory, plus a constructor-theoretic account of life. It has not yet produced novel predictions that distinguish CT from standard physics. Whether it will is open." },
      { color: "#94a3b8", title: "Small research community", text: "Constructor Theory has perhaps a dozen serious practitioners worldwide. Compared to FEP (hundreds), enactivism (hundreds), or process biology (a growing several dozen), the school is small. This could mean it's wrong, or it's right but underexplored, or it's a stable niche." },
    ],
    whenWins: "Reach for Constructor Theory when the question is: what is or isn't physically possible, in principle? Strong fit for foundations of information theory, thermodynamics reformulations, quantum-information no-go theorems, and the nature of computation. Weak fit when the question is empirical-dynamical (what actually happens, fast) — there CT must compete with cleaner machinery from standard physics.",
    compare: [
      { q: "What is primitive?",          spine: "Distinction + Asymmetry",                  this: "Tasks + constructors + counterfactual possibility" },
      { q: "What makes something a system?", spine: "Occupies a level",                      this: "Supports specific task-transformations under some constructor" },
      { q: "What is fundamental?",        spine: "What is (states + dynamics)",              this: "What is possible — modality is primitive, not derived" },
      { q: "Information?",                spine: "Shannon-counted distinctions",              this: "Counterfactual reliability — abilities, not counts" },
      { q: "Modality?",                   spine: "Derived from Pearl's do-calculus at L4+",  this: "Primitive — counterfactuals are the foundation, not a derived modal layer" },
    ],
    tension: "Constructor Theory is the deepest disagreement with the Spine on modality. The Spine derives counterfactuals via Pearl's do-calculus — modality emerges from intervention asymmetry. Constructor Theory inverts: counterfactuals are primitive, and ordinary physics (what actually happens) is downstream. This reframes information itself — not Shannon-counted distinctions, but knowability of counterfactual transformations. The Spine borrows do-calculus operationally; Constructor Theory makes modality the ontological foundation. They cannot both be right about which is primitive — though they might be reconcilable as different stances on the same formal structure.",
  },
};

// ─── ALTERNATIVE-FRAMEWORK DIAGRAMS ──────────────────────────────────────────

function EnactiveDiagram() {
  const col = C.e4;
  return (
    <svg viewBox="0 0 420 310" style={{ width: "100%", height: "auto", display: "block" }}>
      <defs>
        <marker id="enact-arr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z" fill={col} />
        </marker>
        <marker id="enact-arr-rev" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z" fill={C.muted} />
        </marker>
      </defs>
      {/* Environment label */}
      <text x={20} y={22} fill={C.muted} fontSize={11} fontFamily="ui-monospace,monospace" letterSpacing={0.5} fontWeight={700}>ENVIRONMENT</text>
      <text x={20} y={36} fill={C.muted} fontSize={9.5} fontStyle="italic">brought forth through coupling</text>
      {/* Nested circles — cell ⊂ organism ⊂ cognitive ⊂ social */}
      {[
        { r: 130, label: "social",    y: 252 },
        { r: 95,  label: "cognitive", y: 217 },
        { r: 62,  label: "organism",  y: 184 },
        { r: 32,  label: "cell",      y: 150 },
      ].map((c, i) => (
        <g key={i}>
          <circle cx={210} cy={170} r={c.r} fill={`${col}0${4 + i * 2}`} stroke={col} strokeOpacity={0.45 + i * 0.13} strokeWidth={1.2} />
          <text x={210} y={c.y - c.r + 14} textAnchor="middle" fill={col} fontSize={10} fontFamily="ui-monospace,monospace" opacity={0.85}>{c.label}</text>
        </g>
      ))}
      {/* Inner self-production loop (autopoiesis at the cell) */}
      <path d="M 210 152 Q 226 162 224 178 Q 218 192 206 188 Q 196 184 196 172 Q 197 156 210 152 Z"
        fill="none" stroke={col} strokeWidth={1.4} markerEnd="url(#enact-arr)" />
      <text x={210} y={172} textAnchor="middle" fill={col} fontSize={9} fontStyle="italic">autopoiesis</text>
      {/* Sensorimotor coupling — arrows crossing the outermost boundary in both directions */}
      <path d="M 60 130 Q 130 140 178 160" stroke={C.muted} strokeWidth={1.2} fill="none" strokeOpacity={0.6} strokeDasharray="3,2" markerEnd="url(#enact-arr-rev)" />
      <text x={70} y={123} fill={C.muted} fontSize={9} fontFamily="ui-monospace,monospace">perceive</text>
      <path d="M 240 180 Q 310 200 360 220" stroke={C.muted} strokeWidth={1.2} fill="none" strokeOpacity={0.6} strokeDasharray="3,2" markerEnd="url(#enact-arr-rev)" />
      <text x={310} y={213} fill={C.muted} fontSize={9} fontFamily="ui-monospace,monospace">act</text>
      {/* Bottom annotation */}
      <text x={210} y={295} textAnchor="middle" fill={col} fontSize={10.5} fontStyle="italic">same closure logic at every scale — no underlying ladder</text>
    </svg>
  );
}

function CyberneticsDiagram() {
  const col = C.cyb;
  return (
    <svg viewBox="0 0 420 310" style={{ width: "100%", height: "auto", display: "block" }}>
      <defs>
        <marker id="cyb-arr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z" fill={col} />
        </marker>
        <marker id="cyb-arr-d" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z" fill={C.muted} />
        </marker>
      </defs>
      {/* Second-order outer boundary */}
      <rect x={20} y={18} width={380} height={262} rx={10} fill={`${col}06`} stroke={col} strokeOpacity={0.4} strokeWidth={1} strokeDasharray="5,4" />
      <text x={32} y={36} fill={col} fontSize={10} fontFamily="ui-monospace,monospace" fontWeight={700} letterSpacing={0.5}>SECOND-ORDER LOOP — observer included</text>

      {/* Inner first-order loop boxes */}
      {[
        { id: "ctrl",   x: 130, y: 70,  w: 160, h: 44, label: "CONTROLLER",     sub: "regulates" },
        { id: "sys",    x: 130, y: 165, w: 160, h: 44, label: "SYSTEM",         sub: "the regulated" },
        { id: "sensor", x: 290, y: 165, w: 90,  h: 44, label: "SENSOR",         sub: "measures" },
        { id: "dist",   x: 40,  y: 165, w: 80,  h: 44, label: "DISTURBANCE",    sub: "from env" },
        { id: "obs",    x: 130, y: 230, w: 160, h: 36, label: "OBSERVER",       sub: "models the loop" },
      ].map(b => (
        <g key={b.id}>
          <rect x={b.x} y={b.y} width={b.w} height={b.h} rx={5} fill={C.surface2} stroke={col} strokeWidth={1.2} strokeOpacity={b.id === "obs" ? 0.7 : 1} />
          <text x={b.x + b.w / 2} y={b.y + 19} textAnchor="middle" fill={col} fontSize={11} fontWeight={700} fontFamily="ui-monospace,monospace">{b.label}</text>
          <text x={b.x + b.w / 2} y={b.y + 33} textAnchor="middle" fill={C.muted} fontSize={9} fontStyle="italic">{b.sub}</text>
        </g>
      ))}
      {/* Arrows: controller → system */}
      <path d="M 210 114 L 210 165" stroke={col} strokeWidth={1.4} markerEnd="url(#cyb-arr)" />
      <text x={216} y={142} fill={col} fontSize={9} fontFamily="ui-monospace,monospace">control</text>
      {/* System → Sensor */}
      <path d="M 290 187 L 290 187" />
      <path d="M 290 187 L 290 187" />
      {/* System output → Sensor */}
      <path d="M 290 178 L 295 178 L 295 178 L 290 178" />
      {/* From System right edge → Sensor left edge (already adjacent — use feedback below instead) */}
      {/* Sensor → Controller (feedback path going right side up) */}
      <path d="M 335 165 L 335 92 L 290 92" stroke={col} strokeWidth={1.4} fill="none" markerEnd="url(#cyb-arr)" />
      <text x={340} y={130} fill={col} fontSize={9} fontFamily="ui-monospace,monospace">feedback</text>
      {/* Disturbance → System */}
      <path d="M 120 187 L 130 187" stroke={C.muted} strokeWidth={1.3} markerEnd="url(#cyb-arr-d)" />
      {/* Observer → Controller (second-order feedback) */}
      <path d="M 210 230 L 210 215 L 90 215 L 90 80 L 130 80" stroke={col} strokeWidth={1} fill="none" strokeOpacity={0.55} strokeDasharray="3,2" markerEnd="url(#cyb-arr)" />
      <text x={50} y={210} fill={col} fontSize={9} fontFamily="ui-monospace,monospace" opacity={0.7}>2nd order</text>
      {/* Bottom annotation */}
      <text x={210} y={296} textAnchor="middle" fill={col} fontSize={10.5} fontStyle="italic">feedback is primitive — present at every scale worth calling a system</text>
    </svg>
  );
}

function ProcessDiagram() {
  const col = C.pro;
  return (
    <svg viewBox="0 0 420 270" style={{ width: "100%", height: "auto", display: "block" }}>
      <defs>
        <marker id="proc-arr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z" fill={col} />
        </marker>
        <linearGradient id="proc-flow" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%" stopColor={col} stopOpacity={0.05} />
          <stop offset="50%" stopColor={col} stopOpacity={0.18} />
          <stop offset="100%" stopColor={col} stopOpacity={0.05} />
        </linearGradient>
      </defs>
      {/* Flow band — the river of becoming */}
      <rect x={20} y={80} width={380} height={80} fill="url(#proc-flow)" />
      {/* Flow lines */}
      {[95, 110, 125, 140, 155].map((y, i) => (
        <path key={i} d={`M 20 ${y} C 120 ${y - 6}, 220 ${y + 4}, 320 ${y - 2}, 400 ${y}`}
          stroke={col} strokeOpacity={0.45 - i * 0.05} strokeWidth={0.8} fill="none" />
      ))}
      {/* Direction arrow */}
      <line x1={20} y1={70} x2={395} y2={70} stroke={col} strokeOpacity={0.5} strokeWidth={1.2} strokeDasharray="3,3" markerEnd="url(#proc-arr)" />
      <text x={210} y={60} textAnchor="middle" fill={col} fontSize={10} fontFamily="ui-monospace,monospace" letterSpacing={0.5}>BECOMING — time / process</text>

      {/* Eddies = stable patterns ("things") */}
      {[
        { cx: 90,  cy: 118, r: 16, label: "atom",     sub: "fast eddy" },
        { cx: 180, cy: 125, r: 22, label: "organism", sub: "medium eddy" },
        { cx: 290, cy: 120, r: 28, label: "society",  sub: "slow eddy" },
      ].map((e, i) => (
        <g key={i}>
          <circle cx={e.cx} cy={e.cy} r={e.r} fill={C.surface2} stroke={col} strokeWidth={1.4} />
          {/* Swirl */}
          <path d={`M ${e.cx - e.r * 0.5} ${e.cy} A ${e.r * 0.5} ${e.r * 0.5} 0 0 1 ${e.cx + e.r * 0.5} ${e.cy}`}
            fill="none" stroke={col} strokeWidth={1} markerEnd="url(#proc-arr)" />
          <text x={e.cx} y={e.cy + e.r + 14} textAnchor="middle" fill={col} fontSize={10} fontWeight={700}>{e.label}</text>
          <text x={e.cx} y={e.cy + e.r + 25} textAnchor="middle" fill={C.muted} fontSize={9} fontStyle="italic">{e.sub}</text>
        </g>
      ))}
      {/* Forming / dissolving eddy */}
      <circle cx={370} cy={120} r={8} fill="none" stroke={col} strokeOpacity={0.55} strokeWidth={1} strokeDasharray="2,2" />
      <text x={370} y={102} textAnchor="middle" fill={C.muted} fontSize={9} fontStyle="italic">forming...</text>

      {/* Bottom annotation */}
      <text x={210} y={224} textAnchor="middle" fill={col} fontSize={11} fontStyle="italic">"Things" are stabilized whirlpools in the flow of becoming.</text>
      <text x={210} y={242} textAnchor="middle" fill={C.muted} fontSize={10}>The flow is primary; eddies are derivative — even atoms persist by re-occurrence, not by enduring substance.</text>
    </svg>
  );
}

function ActiveInfDiagram() {
  const col = C.aif;
  return (
    <svg viewBox="0 0 420 310" style={{ width: "100%", height: "auto", display: "block" }}>
      <defs>
        <marker id="fep-pred" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z" fill={col} />
        </marker>
        <marker id="fep-err" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z" fill="#fbbf24" />
        </marker>
      </defs>
      {/* External states — outer ring */}
      <rect x={15} y={15} width={390} height={270} rx={12} fill={`${col}05`} stroke={col} strokeOpacity={0.35} strokeWidth={1} />
      <text x={28} y={32} fill={col} fontSize={10} fontFamily="ui-monospace,monospace" fontWeight={700} letterSpacing={0.5}>EXTERNAL  η</text>

      {/* Markov blanket — middle ring with sensory + active states */}
      <rect x={55} y={55} width={310} height={200} rx={9} fill={`${col}09`} stroke={col} strokeOpacity={0.6} strokeWidth={1.3} />
      <text x={68} y={72} fill={col} fontSize={10} fontFamily="ui-monospace,monospace" fontWeight={700} letterSpacing={0.5}>MARKOV BLANKET  b = {"{s, a}"}</text>

      {/* Internal states — innermost */}
      <rect x={120} y={100} width={180} height={140} rx={8} fill={`${col}15`} stroke={col} strokeWidth={1.5} />
      <text x={210} y={120} textAnchor="middle" fill={col} fontSize={11} fontFamily="ui-monospace,monospace" fontWeight={700} letterSpacing={0.5}>INTERNAL  μ</text>
      <text x={210} y={134} textAnchor="middle" fill={C.muted} fontSize={9} fontStyle="italic">generative model</text>

      {/* Hierarchical levels inside internal */}
      {[
        { y: 150, label: "L3: long timescale  →  policies" },
        { y: 170, label: "L2: medium  →  goals" },
        { y: 190, label: "L1: short  →  predictions" },
        { y: 210, label: "L0: micro  →  prediction errors" },
      ].map((lvl, i) => (
        <g key={i}>
          <line x1={130} y1={lvl.y} x2={290} y2={lvl.y} stroke={col} strokeOpacity={0.25} strokeWidth={0.7} />
          <text x={210} y={lvl.y - 3} textAnchor="middle" fill={col} fontSize={8.5} opacity={0.8} fontFamily="ui-monospace,monospace">{lvl.label}</text>
        </g>
      ))}

      {/* Sensory state s — left side */}
      <circle cx={87} cy={155} r={20} fill={C.surface2} stroke={col} strokeWidth={1.3} />
      <text x={87} y={158} textAnchor="middle" fill={col} fontSize={11} fontWeight={700} fontFamily="ui-monospace,monospace">s</text>
      <text x={87} y={184} textAnchor="middle" fill={col} fontSize={9} fontStyle="italic">sensory</text>

      {/* Active state a — right side */}
      <circle cx={333} cy={155} r={20} fill={C.surface2} stroke={col} strokeWidth={1.3} />
      <text x={333} y={158} textAnchor="middle" fill={col} fontSize={11} fontWeight={700} fontFamily="ui-monospace,monospace">a</text>
      <text x={333} y={184} textAnchor="middle" fill={col} fontSize={9} fontStyle="italic">active</text>

      {/* Arrows: external → sensory, internal → active, active → external */}
      <line x1={40} y1={155} x2={67} y2={155} stroke={col} strokeWidth={1.3} markerEnd="url(#fep-pred)" />
      <line x1={353} y1={155} x2={380} y2={155} stroke={col} strokeWidth={1.3} markerEnd="url(#fep-pred)" />
      <line x1={107} y1={155} x2={120} y2={155} stroke={col} strokeWidth={1.3} markerEnd="url(#fep-pred)" />
      <line x1={300} y1={155} x2={313} y2={155} stroke={col} strokeWidth={1.3} markerEnd="url(#fep-pred)" />

      {/* Top predictions cascade arrow + bottom error cascade */}
      <text x={70} y={258} fill={col} fontSize={9.5} fontFamily="ui-monospace,monospace">↓ predictions</text>
      <text x={290} y={258} fill="#fbbf24" fontSize={9.5} fontFamily="ui-monospace,monospace">↑ prediction errors</text>

      {/* Bottom annotation */}
      <text x={210} y={285} textAnchor="middle" fill={col} fontSize={10.5} fontStyle="italic">One principle: minimize F[q]. System = whatever maintains a blanket.</text>
    </svg>
  );
}

function ConstructorDiagram() {
  const col = C.con;
  return (
    <svg viewBox="0 0 420 320" style={{ width: "100%", height: "auto", display: "block" }}>
      <defs>
        <marker id="ct-arr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z" fill={col} />
        </marker>
        <marker id="ct-arr-bad" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z" fill="#ef4444" />
        </marker>
      </defs>
      {/* Header label */}
      <text x={20} y={22} fill={col} fontSize={11} fontFamily="ui-monospace,monospace" letterSpacing={0.5} fontWeight={700}>TASK SPACE — what could happen</text>
      <text x={20} y={36} fill={C.muted} fontSize={9.5} fontStyle="italic">tasks are counterfactual specifications, not events</text>

      {/* Row of tasks (top) — input-output state pairs */}
      {[
        { x: 50,  cx: 80,  label: "T₁",  spec: "(cold,cold) → (hot,cold)", state: "impossible", note: "2nd law forbids" },
        { x: 165, cx: 195, label: "T₂",  spec: "(DNA) → (DNA, DNA)",       state: "possible",   note: "by ribosomes + enzymes" },
        { x: 280, cx: 310, label: "T₃",  spec: "(|ψ⟩) → (|ψ⟩, |ψ⟩)",       state: "impossible", note: "no-cloning (QM)" },
      ].map((t, i) => {
        const bad = t.state === "impossible";
        return (
          <g key={i}>
            <rect x={t.x} y={55} width={60} height={36} rx={5}
              fill={C.surface2} stroke={bad ? "#ef4444" : col} strokeWidth={1.3}
              strokeDasharray={bad ? "3,2" : undefined} />
            <text x={t.cx} y={71} textAnchor="middle" fill={bad ? "#ef4444" : col} fontSize={11} fontWeight={700} fontFamily="ui-monospace,monospace">{t.label}</text>
            <text x={t.cx} y={84} textAnchor="middle" fill={C.muted} fontSize={8} fontFamily="ui-monospace,monospace">{t.spec}</text>
            {/* Impossible: red strike */}
            {bad && (
              <line x1={t.x + 3} y1={88} x2={t.x + 57} y2={58} stroke="#ef4444" strokeWidth={1.5} />
            )}
            {/* Verdict label */}
            <text x={t.cx} y={106} textAnchor="middle" fill={bad ? "#ef4444" : col} fontSize={9} fontStyle="italic">{t.state}</text>
            <text x={t.cx} y={117} textAnchor="middle" fill={C.muted} fontSize={8}>{t.note}</text>
          </g>
        );
      })}

      {/* Constructor box (middle) */}
      <rect x={130} y={150} width={160} height={42} rx={6} fill={`${col}15`} stroke={col} strokeWidth={1.4} />
      <text x={210} y={166} textAnchor="middle" fill={col} fontSize={11} fontWeight={700} fontFamily="ui-monospace,monospace">CONSTRUCTOR C</text>
      <text x={210} y={181} textAnchor="middle" fill={C.muted} fontSize={9} fontStyle="italic">substrate + capability — re-usable</text>

      {/* Arrows: Constructor enables T₂ (the possible task) */}
      <path d="M 195 150 L 195 100" stroke={col} strokeWidth={1.3} fill="none" markerEnd="url(#ct-arr)" />
      <text x={203} y={128} fill={col} fontSize={9} fontStyle="italic">enables</text>

      {/* Crossed-out attempt at T₁ and T₃ */}
      <path d="M 130 165 L 80 100" stroke="#ef4444" strokeWidth={1} fill="none" strokeOpacity={0.55} strokeDasharray="2,2" />
      <text x={95} y={130} fill="#ef4444" fontSize={8.5} fontStyle="italic" opacity={0.7}>no C can enable</text>
      <path d="M 290 165 L 310 100" stroke="#ef4444" strokeWidth={1} fill="none" strokeOpacity={0.55} strokeDasharray="2,2" />

      {/* Possibility-law band (below constructor) */}
      <rect x={20} y={216} width={380} height={42} rx={6} fill={`${col}08`} stroke={col} strokeOpacity={0.45} strokeWidth={1} strokeDasharray="4,3" />
      <text x={32} y={233} fill={col} fontSize={10} fontFamily="ui-monospace,monospace" fontWeight={700} letterSpacing={0.5}>POSSIBILITY LAWS — statements of necessary impossibility</text>
      <text x={32} y={249} fill={C.textDim} fontSize={10} fontFamily="ui-monospace,monospace">"No constructor C exists such that C can perform T₁ (or T₃) reliably and reversibly."</text>

      {/* Bottom annotation */}
      <text x={210} y={288} textAnchor="middle" fill={col} fontSize={11} fontStyle="italic">Existence is downstream of task-possibility.</text>
      <text x={210} y={305} textAnchor="middle" fill={C.muted} fontSize={10}>Information = what resiliently instantiates counterfactuals (knowledge), not Shannon-counted distinctions.</text>
    </svg>
  );
}

function AltLevelCard({ L, active, onSelect, frameworkColor, jumpToConcept }) {
  const col = frameworkColor;
  return (
    <div style={{
      background: active ? `${col}10` : C.surface,
      border: `1px solid ${active ? col : C.border}`,
      borderLeft: `3px solid ${col}`,
      borderRadius: 6,
      marginBottom: 7,
      transition: "background 120ms",
    }}>
      <div onClick={onSelect} style={{ padding: "9px 12px", cursor: "pointer" }}>
        <div style={{ display: "flex", alignItems: "baseline", gap: 8, flexWrap: "wrap" }}>
          <span style={{ fontSize: 9.5, color: col, background: `${col}1c`, border: `1px solid ${col}55`, padding: "1px 6px", borderRadius: 3, letterSpacing: 0.5, fontFamily: "ui-monospace,monospace", fontWeight: 700 }}>{L.id}</span>
          <span style={{ fontSize: 13, fontWeight: 600, color: C.text }}>{L.label}</span>
          {L.symbol && <span style={{ fontSize: 10.5, color: C.muted, fontFamily: "ui-monospace,monospace", fontStyle: "italic" }}>{L.symbol}</span>}
        </div>
        {!active && (
          <div style={{ fontSize: 11.5, color: C.textDim, marginTop: 4, lineHeight: 1.5 }}>{L.tagline}</div>
        )}
      </div>
      {active && (
        <div style={{ padding: "0 12px 11px 12px" }}>
          <div style={{ fontSize: 11.5, color: C.muted, marginBottom: 8, fontStyle: "italic", lineHeight: 1.5 }}>{L.tagline}</div>
          <div style={{ fontSize: 12, color: C.text, lineHeight: 1.65, whiteSpace: "pre-line", marginBottom: 9 }}>
            {L.detail.split("**").map((p, i) => i % 2 === 1 ? <strong key={i} style={{ color: C.text }}>{p}</strong> : p)}
          </div>
          {L.spineAnalog && (
            <div style={{ background: `${C.sr}0a`, border: `1px solid ${C.sr}33`, borderLeft: `2px solid ${C.sr}`, borderRadius: 4, padding: "7px 10px", marginBottom: 8 }}>
              <div style={{ fontSize: 9.5, color: C.sr, fontWeight: 700, letterSpacing: 0.5, marginBottom: 3, fontFamily: "ui-monospace,monospace" }}>SPINE ANALOG</div>
              <div style={{ fontSize: 11.5, color: C.text, lineHeight: 1.5 }}>{L.spineAnalog}</div>
            </div>
          )}
          {L.examples && (
            <div style={{ fontSize: 11, color: C.muted, fontStyle: "italic", lineHeight: 1.5 }}>
              <span style={{ color: C.textDim, fontWeight: 600, fontStyle: "normal" }}>Examples: </span>{L.examples}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function AlternativeView({ viewId, jumpToConcept }) {
  const meta = SYS_VIEWS.find(v => v.id === viewId);
  const data = ALT_FRAMEWORKS[viewId];
  const [altSel, setAltSel] = useState(null);
  if (!meta || !data) return null;
  const col = meta.color;

  const Diagram = {
    enactive:    EnactiveDiagram,
    cybernetic:  CyberneticsDiagram,
    process:     ProcessDiagram,
    fep:         ActiveInfDiagram,
    constructor: ConstructorDiagram,
  }[viewId];

  const sectionLabelStyle = { fontSize: 9.5, color: col, fontWeight: 700, letterSpacing: 0.6, textTransform: "uppercase", marginBottom: 8, fontFamily: "ui-monospace,monospace" };

  return (
    <div>
      {/* Header */}
      <div style={{ background: C.surface, border: `1px solid ${col}55`, borderLeft: `3px solid ${col}`, borderRadius: 8, padding: "14px 16px", marginBottom: 12 }}>
        <div style={{ display: "flex", alignItems: "baseline", gap: 10, flexWrap: "wrap", marginBottom: 5 }}>
          <span style={{ fontSize: 9.5, color: col, background: `${col}18`, border: `1px solid ${col}44`, padding: "1px 8px", borderRadius: 3, letterSpacing: 0.6, fontFamily: "ui-monospace,monospace", fontWeight: 700 }}>
            ALTERNATIVE FRAMING
          </span>
          <span style={{ fontSize: 15, fontWeight: 700, color: col }}>{meta.school}</span>
        </div>
        <div style={{ fontSize: 11, color: C.muted, marginBottom: 8, fontFamily: "ui-monospace,monospace" }}>
          {meta.who} · <span style={{ color: C.textDim }}>{data.era}</span>
        </div>
        <div style={{ fontSize: 13, color: C.text, lineHeight: 1.6, fontStyle: "italic" }}>{data.claim}</div>
      </div>

      {/* Diagram */}
      <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 8, padding: 10, marginBottom: 12 }}>
        <Diagram />
      </div>

      {/* Primitives */}
      <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 8, padding: "12px 14px", marginBottom: 12 }}>
        <div style={sectionLabelStyle}>Primitives — what this framework starts with</div>
        <div style={{ display: "flex", flexDirection: "column", gap: 7 }}>
          {data.primitives.map((p, i) => (
            <div key={i} style={{ background: C.surface2, borderLeft: `2px solid ${col}`, padding: "8px 11px", borderRadius: 4 }}>
              <div style={{ fontSize: 12.5, fontWeight: 600, color: C.text, marginBottom: 3 }}>{p.name}</div>
              <div style={{ fontSize: 11.5, color: C.textDim, lineHeight: 1.55 }}>{p.desc}</div>
            </div>
          ))}
        </div>
      </div>

      {/* Component / level cards */}
      {data.levels && data.levels.length > 0 && (
        <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 8, padding: "12px 14px", marginBottom: 12 }}>
          <div style={sectionLabelStyle}>Components — this framework's own hierarchy</div>
          <div style={{ fontSize: 11, color: C.muted, marginBottom: 9, fontStyle: "italic", lineHeight: 1.5 }}>
            Tap any card to expand its detail and see how it maps to the Spine. These are NOT additive levels like L0–L8 — they are the framework's own structural distinctions.
          </div>
          {data.levels.map(L => (
            <AltLevelCard key={L.id} L={L}
              active={altSel === L.id}
              onSelect={() => setAltSel(altSel === L.id ? null : L.id)}
              frameworkColor={col}
              jumpToConcept={jumpToConcept} />
          ))}
        </div>
      )}

      {/* Systemhood + Hierarchy */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr", gap: 10, marginBottom: 12 }}>
        <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 8, padding: "12px 14px" }}>
          <div style={sectionLabelStyle}>Systemhood criterion</div>
          <div style={{ fontSize: 12, color: C.text, lineHeight: 1.6 }}>{data.systemhood}</div>
        </div>
        <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 8, padding: "12px 14px" }}>
          <div style={sectionLabelStyle}>Hierarchy / structure view</div>
          <div style={{ fontSize: 12, color: C.text, lineHeight: 1.6 }}>{data.hierarchy}</div>
        </div>
      </div>

      {/* Bridge to Spine */}
      {data.bridgeToSpine && data.bridgeToSpine.length > 0 && (
        <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 8, padding: "12px 14px", marginBottom: 12 }}>
          <div style={sectionLabelStyle}>Bridge to the Spine — concept-by-concept mapping</div>
          <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
            <div style={{ display: "grid", gridTemplateColumns: "minmax(0, 1fr) minmax(0, 1.1fr) minmax(0, 1.4fr)", gap: 6, fontSize: 10, fontFamily: "ui-monospace,monospace", color: C.muted, fontWeight: 700, letterSpacing: 0.5, padding: "0 4px 4px", borderBottom: `1px solid ${C.border}` }}>
              <span style={{ color: col }}>{meta.short}</span>
              <span style={{ color: C.sr }}>SPINE</span>
              <span>NOTE</span>
            </div>
            {data.bridgeToSpine.map((r, i) => (
              <div key={i} style={{ display: "grid", gridTemplateColumns: "minmax(0, 1fr) minmax(0, 1.1fr) minmax(0, 1.4fr)", gap: 6, padding: "6px 4px", fontSize: 11.5, lineHeight: 1.5, borderBottom: i < data.bridgeToSpine.length - 1 ? `1px solid ${C.border}55` : "none" }}>
                <span style={{ color: C.text, fontWeight: 600 }}>{r.their}</span>
                <span style={{ color: C.textDim }}>{r.spine}</span>
                <span style={{ color: C.textDim, fontStyle: "italic" }}>{r.note}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Side-by-side comparison */}
      <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 8, padding: "12px 14px", marginBottom: 12 }}>
        <div style={sectionLabelStyle}>Side-by-side — same questions, both answers</div>
        <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
          <div style={{ display: "grid", gridTemplateColumns: "minmax(0, 1.1fr) minmax(0, 1.2fr) minmax(0, 1.2fr)", gap: 6, fontSize: 10, fontFamily: "ui-monospace,monospace", color: C.muted, fontWeight: 700, letterSpacing: 0.5, padding: "0 4px 4px", borderBottom: `1px solid ${C.border}` }}>
            <span>QUESTION</span>
            <span style={{ color: C.sr }}>SPINE</span>
            <span style={{ color: col }}>{meta.short}</span>
          </div>
          {data.compare.map((r, i) => (
            <div key={i} style={{ display: "grid", gridTemplateColumns: "minmax(0, 1.1fr) minmax(0, 1.2fr) minmax(0, 1.2fr)", gap: 6, padding: "6px 4px", fontSize: 11.5, lineHeight: 1.5, borderBottom: i < data.compare.length - 1 ? `1px solid ${C.border}55` : "none" }}>
              <span style={{ color: C.text, fontWeight: 600 }}>{r.q}</span>
              <span style={{ color: C.textDim }}>{r.spine}</span>
              <span style={{ color: C.textDim }}>{r.this}</span>
            </div>
          ))}
        </div>
      </div>

      {/* When to reach for this */}
      {data.whenWins && (
        <div style={{ background: `${col}0a`, border: `1px solid ${col}55`, borderLeft: `3px solid ${col}`, borderRadius: 6, padding: "10px 14px", marginBottom: 12 }}>
          <div style={{ fontSize: 9.5, color: col, fontWeight: 700, letterSpacing: 0.6, textTransform: "uppercase", marginBottom: 5, fontFamily: "ui-monospace,monospace" }}>
            When to reach for {meta.short.toLowerCase()}
          </div>
          <div style={{ fontSize: 12, color: C.text, lineHeight: 1.6 }}>{data.whenWins}</div>
        </div>
      )}

      {/* Caveats / Critiques */}
      {data.caveats && data.caveats.length > 0 && (
        <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 8, padding: "12px 14px", marginBottom: 12 }}>
          <div style={sectionLabelStyle}>Caveats &amp; critiques — where this framework itself is contested</div>
          <div style={{ fontSize: 11, color: C.muted, marginBottom: 9, fontStyle: "italic", lineHeight: 1.5 }}>
            The same critical treatment applied to the Spine: not "wrong," but contested. The colors indicate severity — red for foundational critiques, amber for serious-but-debated, grey for sociological/practical concerns.
          </div>
          <ol style={{ margin: 0, paddingLeft: 18, fontSize: 11.5, color: C.text, lineHeight: 1.6 }}>
            {data.caveats.map((c, i) => (
              <li key={i} style={{ marginBottom: i < data.caveats.length - 1 ? 7 : 0 }}>
                <strong style={{ color: c.color }}>{c.title}.</strong>{" "}
                <span style={{ color: C.textDim }}>{c.text}</span>
              </li>
            ))}
          </ol>
        </div>
      )}

      {/* Key tension with the Spine */}
      <div style={{ background: `${col}10`, border: `1px solid ${col}55`, borderLeft: `3px solid ${col}`, borderRadius: 6, padding: "12px 14px" }}>
        <div style={{ fontSize: 9.5, color: col, fontWeight: 700, letterSpacing: 0.6, textTransform: "uppercase", marginBottom: 6, fontFamily: "ui-monospace,monospace" }}>
          Key tension with the Spine
        </div>
        <div style={{ fontSize: 12, color: C.text, lineHeight: 1.65 }}>{data.tension}</div>
      </div>
    </div>
  );
}

function SubtabNav({ views, current, onChange }) {
  return (
    <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 8, padding: 6, marginBottom: 12, display: "flex", gap: 4, overflowX: "auto", flexWrap: "wrap" }}>
      {views.map(v => {
        const active = v.id === current;
        return (
          <button key={v.id} onClick={() => onChange(v.id)}
            style={{
              background: active ? `${v.color}1c` : "transparent",
              border: `1px solid ${active ? v.color : "transparent"}`,
              color: active ? v.color : C.muted,
              padding: "6px 11px", fontSize: 11.5, fontWeight: active ? 700 : 600,
              borderRadius: 5, cursor: "pointer", fontFamily: "inherit",
              transition: "all 100ms", whiteSpace: "nowrap",
            }}>
            {v.label}
          </button>
        );
      })}
    </div>
  );
}

function SystemTypesTab({ jumpToConcept }) {
  const [view, setView] = useState("spine");
  const [sel, setSel] = useState("L5");
  // All indicators always on — user requested no filter buttons
  const showDownward = true;
  const showInfo = true;
  const showTime = true;

  // Group by phase
  const staticLevels    = SYSTEM_LEVELS.filter(l => ["L0","L1","L2"].includes(l.id));
  const l3               = SYSTEM_LEVELS.find(l => l.id === "L3");
  const l4Branches       = SYSTEM_LEVELS.filter(l => l.id.startsWith("L4-"));
  const l5               = SYSTEM_LEVELS.find(l => l.id === "L5");
  const cognitiveLevels  = SYSTEM_LEVELS.filter(l => ["L6","L7","L8"].includes(l.id));

  const cardProps = { jumpToConcept, showTime, showInfo, showDownward };

  return (
    <div style={{ padding: "16px 14px 60px", maxWidth: 740, margin: "0 auto" }}>

      {/* Shared intro — explains why there are five views */}
      <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 8, padding: "12px 14px", marginBottom: 10 }}>
        <div style={{ fontSize: 14.5, fontWeight: 600, color: C.text, marginBottom: 5 }}>
          System Types — six ways to carve up systemhood
        </div>
        <div style={{ fontSize: 12, color: C.textDim, lineHeight: 1.6 }}>
          The <span style={{ color: C.sr, fontWeight: 600 }}>Spine</span> is this atlas's main typology: levels of being built from Distinction + Asymmetry. The five alternative subtabs ({SYS_VIEWS.slice(1).map((v, i) => (
            <span key={v.id}><span style={{ color: v.color, fontWeight: 600 }}>{v.label}</span>{i < SYS_VIEWS.length - 2 ? ", " : ""}</span>
          ))}) take genuinely different primitives and arrive at genuinely different system ontologies. Each is internally coherent and each disagrees with the Spine somewhere it actually matters.
        </div>
        <div style={{ fontSize: 11.5, color: C.muted, marginTop: 6, lineHeight: 1.5, fontStyle: "italic" }}>
          The alternatives are not "wrong" — they answer different questions and accept different costs. Use this tab to see what's at stake in choosing the Spine.
        </div>
      </div>

      <SubtabNav views={SYS_VIEWS} current={view} onChange={setView} />

      {view !== "spine" && <AlternativeView viewId={view} jumpToConcept={jumpToConcept} />}

      {view === "spine" && (<>

      {/* Header */}
      <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 8, padding: "12px 14px", marginBottom: 12 }}>
        <div style={{ fontSize: 14.5, fontWeight: 600, color: C.text, marginBottom: 5 }}>
          Spine — primitives to social systems
        </div>
        <div style={{ fontSize: 12, color: C.textDim, lineHeight: 1.6 }}>
          Each level adds one ingredient. Three phases: <span style={{ color: PHASES[0].color, fontWeight: 600 }}>static</span> (L0–L2, no time), <span style={{ color: PHASES[1].color, fontWeight: 600 }}>dynamical</span> (L3–L5, time + energy + adaptation), <span style={{ color: PHASES[2].color, fontWeight: 600 }}>cognitive</span> (L6–L8, models of models). <span style={{ color: C.text }}>Partial order, not developmental ladder</span> — a steam engine never becomes a bacterium.
        </div>
        <div style={{ fontSize: 11.5, color: C.muted, marginTop: 6, lineHeight: 1.5, fontStyle: "italic" }}>
          Tap any level to expand. Time character (t↔/t→), information quantity, and downward causation are shown inline. Status badges flag which claims are consensus vs. atlas-positions vs. contested.
        </div>
        <div style={{ display: "flex", gap: 12, marginTop: 8, flexWrap: "wrap" }}>
          {["consensus", "atlas-position", "contested", "placeholder"].map(k => (
            <div key={k} style={{ display: "flex", alignItems: "center", gap: 5 }}>
              <div style={{ width: 9, height: 9, borderRadius: 2, background: STATUS_COLOR[k] }} />
              <span style={{ fontSize: 10.5, color: C.muted, fontFamily: "ui-monospace, monospace" }}>{STATUS_LABEL[k]}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Diagram — compact overview map */}
      <SystemTypesDiagram sel={sel} setSel={setSel} />

      {/* STATIC PHASE */}
      <PhaseHeader phase={PHASES[0]} />
      <div style={{ display: "flex", flexDirection: "column", gap: 6, marginBottom: 6 }}>
        {staticLevels.map(L => (
          <LevelCard key={L.id} L={L} active={sel === L.id} onSelect={setSel} {...cardProps} />
        ))}
      </div>

      {/* DYNAMICAL PHASE */}
      <PhaseHeader phase={PHASES[1]} />
      <div style={{ display: "flex", flexDirection: "column", gap: 6, marginBottom: 6 }}>
        <LevelCard L={l3} active={sel === "L3"} onSelect={setSel} {...cardProps} />

        {/* L4 cluster — three branches grouped */}
        <div style={{
          background: `${LEVEL_COLOR.dynamic}06`,
          border: `1px dashed ${LEVEL_COLOR.dynamic}55`,
          borderRadius: 6,
          padding: "8px 8px 10px",
          marginTop: 4,
        }}>
          <div style={{ fontSize: 10, color: LEVEL_COLOR.dynamic, fontWeight: 700, letterSpacing: 0.7, textTransform: "uppercase", marginBottom: 7, paddingLeft: 4, fontFamily: "ui-monospace,monospace" }}>
            L4 — three orthogonal upgrades · usually co-occur in practice
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 5 }}>
            {l4Branches.map(L => (
              <LevelCard key={L.id} L={L} active={sel === L.id} onSelect={setSel} {...cardProps} narrow={true} />
            ))}
          </div>
          <div style={{ fontSize: 10, color: C.muted, fontStyle: "italic", textAlign: "center", marginTop: 8 }}>
            ↓ all three converge to L5
          </div>
        </div>

        <LevelCard L={l5} active={sel === "L5"} onSelect={setSel} {...cardProps} />
      </div>

      {/* COGNITIVE PHASE */}
      <PhaseHeader phase={PHASES[2]} />
      <div style={{ display: "flex", flexDirection: "column", gap: 6, marginBottom: 14 }}>
        {cognitiveLevels.map((L, i) => (
          <div key={L.id} style={{ position: "relative" }}>
            <LevelCard L={L} active={sel === L.id} onSelect={setSel} {...cardProps} />
            {i < cognitiveLevels.length - 1 && (
              <div style={{ fontSize: 9.5, color: PHASES[2].color, opacity: 0.6, textAlign: "center", margin: "3px 0", fontFamily: "ui-monospace,monospace" }}>
                ↓ model now includes ↓
              </div>
            )}
          </div>
        ))}
      </div>

      {/* BRIDGE — Primitives mapping (kept from before) */}
      <div style={{ background: C.surface, border: "1px solid #a78bfa55", borderLeft: "3px solid #a78bfa", borderRadius: 6, padding: "12px 14px", marginBottom: 12 }}>
        <div style={{ fontSize: 13.5, fontWeight: 600, color: "#a78bfa", marginBottom: 4 }}>
          Bridge to the Primitives tab
        </div>
        <div style={{ fontSize: 11.5, color: C.textDim, lineHeight: 1.55, marginBottom: 8 }}>
          The <span style={{ color: "#a78bfa", fontWeight: 600 }}>Primitives tab</span> shows the <em>derivation hierarchy</em> — what gets built from the two primitives. This tab shows the <em>ontology of system kinds</em> — what systems exist using those constructions. Duals.
        </div>
        <div style={{ fontSize: 11, color: "#fbbf24", lineHeight: 1.5, fontStyle: "italic", marginBottom: 10 }}>
          ⚠ "Derivation N" in Primitives ≠ "L-N" here. The two numbering schemes are independent.
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
          {[
            { p: "Distinction",       pkind: "primitive",     s: "used throughout",             w: "Symmetric difference",        direct: false },
            { p: "Asymmetry",         pkind: "primitive",     s: "used throughout",             w: "Directed difference",         direct: false },
            { p: "Identity",          pkind: "derivation 1",  s: "absorbed into L1 set",        w: "Zero-distinction limit",      direct: false },
            { p: "Information",       pkind: "derivation 1",  s: "transverse — all levels",     w: "Quantified distinction",      direct: false },
            { p: "Ordering",          pkind: "derivation 1",  s: "built into L3 dynamics",      w: "Sequence structure",          direct: false },
            { p: "Causation",         pkind: "derivation 1",  s: "built into L4-thermo + L5+",  w: "Intervention asymmetry",      direct: false },
            { p: "Structure",         pkind: "derivation 2",  s: "→ L2 structured system",      w: "Directed graph",              direct: true  },
            { p: "Process",           pkind: "derivation 2",  s: "→ L3 dynamical system",       w: "Time evolution",              direct: true  },
            { p: "Irreversibility",   pkind: "derivation 2",  s: "→ L4-thermodynamic",          w: "One-way time",                direct: true  },
            { p: "Emergence",         pkind: "derivation 3",  s: "→ L4-complex",                w: "Macro causation",             direct: true  },
            { p: "Reflexivity",       pkind: "derivation 3",  s: "→ L7 reflexive",              w: "Self-modeling",               direct: true  },
          ].map((r, i) => (
            <div key={i} style={{ background: r.direct ? "#a78bfa12" : C.surface2, border: `1px solid ${r.direct ? "#a78bfa44" : C.border}`, borderRadius: 5, padding: "7px 10px" }}>
              <div style={{ display: "flex", justifyContent: "space-between", gap: 8, flexWrap: "wrap" }}>
                <div>
                  <span style={{ fontSize: 12.5, color: C.text, fontWeight: r.direct ? 700 : 500 }}>{r.p}</span>
                  <span style={{ fontSize: 9.5, color: C.muted, marginLeft: 6, fontFamily: "ui-monospace,monospace", letterSpacing: 0.3 }}>{r.pkind}</span>
                </div>
                <div style={{ fontSize: 10.5, color: r.direct ? "#a78bfa" : C.muted, fontFamily: "ui-monospace,monospace" }}>{r.s}</div>
              </div>
              <div style={{ fontSize: 11, color: C.textDim, marginTop: 3 }}>{r.w}</div>
            </div>
          ))}
        </div>
      </div>

      {/* Time, Noether, quantum — the deeper structure */}
      <div style={{ background: C.surface, border: "1px solid #9333ea55", borderLeft: "3px solid #9333ea", borderRadius: 6, padding: "12px 14px", marginBottom: 12 }}>
        <div style={{ fontSize: 13.5, fontWeight: 600, color: "#9333ea", marginBottom: 6 }}>
          Time, Noether, quantum — the deeper structure
        </div>
        <div style={{ fontSize: 11.5, color: C.textDim, marginBottom: 10, lineHeight: 1.55 }}>
          Two distinct concepts of time enter the hierarchy at different levels. Noether's theorem operates at L3 (about laws being invariant, not about direction). Quantum mechanics straddles the L3↔L4-thermo seam via decoherence.
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          <div style={{ background: C.surface2, borderLeft: `2px solid ${LEVEL_COLOR.dynamic}`, padding: "8px 10px", borderRadius: 4 }}>
            <div style={{ fontSize: 11.5, fontWeight: 600, color: C.text, marginBottom: 4 }}>
              <code style={{ color: "#9333ea", fontFamily: "ui-monospace,monospace" }}>t ↔</code> Ordering time at L3
            </div>
            <div style={{ fontSize: 11, color: C.textDim, lineHeight: 1.55 }}>
              Time as parameter / sequence index. Reversible — Hamiltonian, Schrödinger, all conservative dynamics. Noether's theorem: continuous symmetries → conserved quantities. Time-translation symmetry → energy. <strong style={{ color: "#fbbf24" }}>This is symmetry of laws, not direction of time.</strong>
            </div>
          </div>
          <div style={{ background: C.surface2, borderLeft: `2px solid ${LEVEL_COLOR.thermo}`, padding: "8px 10px", borderRadius: 4 }}>
            <div style={{ fontSize: 11.5, fontWeight: 600, color: C.text, marginBottom: 4 }}>
              <code style={{ color: "#9333ea", fontFamily: "ui-monospace,monospace" }}>t →</code> Thermodynamic arrow at L4-thermo
            </div>
            <div style={{ fontSize: 11, color: C.textDim, lineHeight: 1.55 }}>
              Direction emerges from boundary conditions (low-entropy initial state) + coarse-graining, not from laws. Boltzmann's arrow. For quantum systems: decoherence is the L3→L4-thermo bridge — environment-induced exponential decay of coherences makes evolution effectively irreversible.
            </div>
          </div>
        </div>
      </div>

      {/* Caveats */}
      <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 8, padding: "12px 14px", marginBottom: 12 }}>
        <div style={{ fontSize: 13.5, fontWeight: 600, color: C.text, marginBottom: 8 }}>
          Caveats — what this hierarchy simplifies or contests
        </div>
        <ol style={{ margin: 0, paddingLeft: 18, fontSize: 12, color: C.text, lineHeight: 1.65 }}>
          <li style={{ marginBottom: 7 }}><strong style={{ color: C.muted }}>L0 is a placeholder, not a level.</strong> By the atlas's own H=0 ⟺ no-structure criterion, L0 has no informational content and no physical instance. Treat it as the empty stage before the construction begins.</li>
          <li style={{ marginBottom: 7 }}><strong style={{ color: C.muted }}>L2 has no natural instances.</strong> Every physical structure in the universe is time-extended (L3 or above). L2 examples (periodic table, schemas, snapshots) are human artifacts or modeling projections. Useful abstraction; not a kind of system that exists in nature.</li>
          <li style={{ marginBottom: 7 }}><strong style={{ color: LEVEL_COLOR.adaptive }}>L4 → L5 is the load-bearing claim — with edge cases.</strong> The conjunction (irreversibility + emergence + openness) is a strong heuristic for physical adaptive systems. RL agents in simulation lack a direct thermodynamic floor; BZ-style chemical oscillators satisfy the conjunction without being adaptive. The deeper requirement is a directional cost gradient driving selection-like dynamics — thermodynamics is one substrate that supplies it.</li>
          <li style={{ marginBottom: 7 }}><strong style={{ color: LEVEL_COLOR.adaptive }}>Living ≠ adaptive.</strong> The atlas treats them as coextensive but life is more restrictive — autopoiesis (Maturana-Varela), metabolism (Schrödinger, Kauffman), reproduction with heredity. A self-organizing chemical clock is adaptive but not alive. Consider this an unmarked L5-living sub-type.</li>
          <li style={{ marginBottom: 7 }}><strong style={{ color: LEVEL_COLOR.thermo }}>L4 siblings are entangled.</strong> Thermo and Open usually co-occur; Complex systems are usually thermodynamic in practice. The "three orthogonal upgrades" framing is cleaner than reality.</li>
          <li style={{ marginBottom: 7 }}><strong style={{ color: "#fbbf24" }}>L4-complex: EI is one measure among many.</strong> ⚠ Hoel's causal emergence depends on a uniform intervention prior; Dewhurst (2021) and Eberhardt-Lee argue this is artificial and the resulting causation is "thin." Alternatives: Cμ (Crutchfield), Φ (Tononi, contested), logical depth (Bennett), effective complexity (Gell-Mann). Atlas chooses EI; the choice is a position.</li>
          <li style={{ marginBottom: 7 }}><strong style={{ color: LEVEL_COLOR.dynamic }}>L3 reversibility holds for Hamiltonian/unitary only.</strong> Classical dissipative chaos (Lorenz attractor) is deterministic dynamical but not time-symmetric. Sits awkwardly between L3 and L4-thermo.</li>
          <li style={{ marginBottom: 7 }}><strong style={{ color: LEVEL_COLOR.dynamic }}>Quantum doesn't fit cleanly at L3.</strong> Hilbert-space structure, superposition, entanglement, and contextuality have no classical L3 analog. The L3↔L4-thermo bridge via decoherence is the orthodox mechanism but interpretation-dependent (Everett, GRW, Bohmian, QBism give different stories).</li>
          <li style={{ marginBottom: 7 }}><strong style={{ color: LEVEL_COLOR.cognitive }}>L6 hides huge variation — and rests on representationalism.</strong> Five sub-types (statistical, learned, embodied, symbolic, collective) are structurally different. 4E cognition / radical enactivism (Hutto, Myin, Di Paolo) rejects the representationalist framing this hierarchy implicitly uses.</li>
          <li style={{ marginBottom: 7 }}><strong style={{ color: LEVEL_COLOR.reflexive }}>L7's deflationary verdict is a position, not a finding.</strong> Critical Realism, Phenomenology, Powers metaphysics, and Enactivism each hold that reflexivity introduces irreducibly novel properties. The hard problem of consciousness is unresolved. Atlas adopts the structural-realist verdict to preserve naturalism — at the cost of treating a substantive debate as settled.</li>
          <li style={{ marginBottom: 7 }}><strong style={{ color: LEVEL_COLOR.reflexive }}>L7 ↔ L8 ordering is contested.</strong> Standard view: self-modeling before social. "I am because we are" (Vygotsky, Mead, ubuntu): reflexivity emerges <em>from</em> social embedding — L8 precedes L7. The deeper implication: a strictly linear spine may be wrong; a co-emergent architecture at the top of the hierarchy may be needed.</li>
          <li style={{ marginBottom: 7 }}><strong style={{ color: "#ef4444" }}>Downward causation is constraint-imposition, not Kim-style macro→micro causation.</strong> The atlas adopts the Juarrero/Hoel/Ellis reading: macro states constrain the space of micro trajectories without directly causing micro events. Kim's exclusion argument targets the latter, not the former. This commitment is not in the original atlas — it is added to address the standard philosophical objection.</li>
          <li style={{ marginBottom: 7 }}><strong style={{ color: "#9333ea" }}>Multiple arrows of time exist.</strong> The hierarchy shows two (ordering + thermodynamic). Physics also recognizes cosmological, radiative, psychological, and causal arrows. They may all reduce to the thermodynamic arrow, but the reduction is contested.</li>
          <li style={{ marginBottom: 7 }}><strong style={{ color: C.muted }}>Invisible orthogonal dimensions.</strong> The linear spine collapses several dimensions that are structurally important and run perpendicular to the level axis:
            <ul style={{ margin: "4px 0 0 0", paddingLeft: 18 }}>
              <li><strong>Coupling</strong> (loose/medium/tight) — see Coupling note below</li>
              <li><strong>Substrate</strong> (biological, silicon, social, abstract) — a brain at L4-complex and a transformer at L4-complex share a level but differ massively</li>
              <li><strong>Scale</strong> (micro/meso/macro) — turbulent flow, organism, economy all hit L4-complex at different scales</li>
              <li><strong>Stochasticity</strong> (deterministic vs probabilistic) — Hamiltonian flow and a Markov chain are both L3 with very different info theory</li>
              <li><strong>Discreteness</strong> (continuous vs discrete time/state) — affects which info measures even apply</li>
            </ul>
            A complete typology would be a multi-dimensional manifold; this spine is one slice through it.</li>
          <li style={{ marginBottom: 0 }}><strong style={{ color: "#ef4444" }}>Tension with "Researching Open Systems" tab.</strong> That tab argues against bounding/individuating social systems (use operational closure, flow tracking instead). This tab relies on individuated levels. The tension is real — System Types gives ontological types; Researching gives methodological strategies for messy reality.</li>
        </ol>
      </div>

      {/* Coupling note */}
      <div style={{ background: `${C.accent}0a`, border: `1px solid ${C.accent}44`, borderLeft: `3px solid ${C.accent}`, borderRadius: 6, padding: "10px 14px" }}>
        <div style={{ fontSize: 11, color: C.accent, fontWeight: 700, letterSpacing: 0.5, textTransform: "uppercase", marginBottom: 5 }}>The dimension the spine collapses</div>
        <div style={{ fontSize: 12, color: C.text, lineHeight: 1.65, whiteSpace: "pre-line" }}>
          {COUPLING_NOTE.split("**").map((p, i) => i % 2 === 1 ? <strong key={i} style={{ color: C.text }}>{p}</strong> : p)}
        </div>
      </div>

      </>)}
    </div>
  );
}

function ToggleBtn({ active, onClick, color, children }) {
  return (
    <button onClick={onClick}
      style={{
        background: active ? `${color}1c` : C.surface,
        border: `1px solid ${active ? color : C.border}`,
        color: active ? color : C.muted,
        padding: "6px 12px", fontSize: 11.5, fontWeight: 600,
        borderRadius: 5, cursor: "pointer", fontFamily: "inherit",
        transition: "all 100ms",
      }}>
      {children}
    </button>
  );
}

export default function ComplexityAtlas() {
  const [tab, setTab] = useState("concepts");
  const [selectedId, setSelectedId] = useState(null);
  const [activeViews, setActiveViews] = useState({
    pc: true, ait: true, cm: true, ci: true, ce: true, aif: true,
    evo: true, net: true, th: true, at: true,
    pow: true, pro: true, mec: true, cr: true, sub: true,
    ct: true, cyb: true, phe: true, e4: true, pcm: true, con: true,
  });
  const [activeCluster, setActiveCluster] = useState("all");
  const [search, setSearch] = useState("");
  const [exampleIdx, setExampleIdx] = useState(0);
  const [methodIdx, setMethodIdx] = useState(0);

  const filtered = useMemo(() => {
    const s = search.toLowerCase().trim();
    return CONCEPTS.filter(c => {
      if (activeCluster !== "all" && c.cluster !== activeCluster) return false;
      if (!s) return true;
      return (
        c.name.toLowerCase().includes(s) ||
        c.plain.toLowerCase().includes(s) ||
        (c.sr && c.sr.toLowerCase().includes(s)) ||
        (c.it && c.it.toLowerCase().includes(s))
      );
    });
  }, [activeCluster, search]);

  const selected = selectedId ? CONCEPTS.find(c => c.id === selectedId) : null;
  const toggleView = (key) => setActiveViews(v => ({ ...v, [key]: !v[key] }));
  const jumpToConcept = (id) => { setTab("concepts"); setSelectedId(id); };

  return (
    <div style={{
      background: C.bg, color: C.text, minHeight: "100vh",
      fontFamily: "'IBM Plex Sans', system-ui, -apple-system, sans-serif",
      fontSize: 13.5, lineHeight: 1.55,
    }}>
      {/* HEADER */}
      <div style={{
        borderBottom: `1px solid ${C.border}`,
        padding: "22px 24px 0",
        background: `linear-gradient(180deg, ${C.surface} 0%, ${C.bg} 100%)`,
      }}>
        <div style={{ display: "flex", alignItems: "baseline", gap: 12, flexWrap: "wrap", marginBottom: 6 }}>
          <div style={{ fontSize: 19, fontWeight: 600, letterSpacing: -0.3 }}>Complexity Atlas</div>
          <div style={{ fontSize: 11, color: C.muted, fontFamily: "ui-monospace, monospace" }}>
            {CONCEPTS.length} concepts · {EXAMPLES.length} examples · {METHODS.length} methods · {Object.keys(FRAMEWORKS).length} frameworks
          </div>
        </div>
        <div style={{ fontSize: 12.5, color: C.textDim, maxWidth: 900, marginBottom: 4 }}>
          A working field guide for complexity theory.
          <span style={{ color: C.sr, fontWeight: 600 }}> Structural Realism </span>
          and
          <span style={{ color: C.it, fontWeight: 600 }}> Information Theory </span>
          anchor every concept; twelve productive frameworks and nine metaphysical systems toggle as views.
          <span style={{ color: C.decision }}> Decision points</span>,
          <span style={{ color: C.open }}> open questions</span>, and
          <span style={{ color: "#ef4444" }}> opposing views </span>
          surface where commitments propagate, remain unresolved, or are contested.
        </div>
        <div style={{ display: "flex", gap: 5, marginTop: 12, flexWrap: "wrap", paddingBottom: 2 }}>
          {[
            { k: "concepts",    label: "Concepts" },
            { k: "primitives",  label: "Primitives" },
            { k: "systemtypes", label: "System Types" },
            { k: "research",    label: "Researching" },
            { k: "examples",    label: "Examples" },
            { k: "methods",     label: "Methods" },
            { k: "practice",    label: "Practice" },
            { k: "agents",      label: "Agents" },
            { k: "frameworks",  label: "Frameworks" },
            { k: "graph",       label: "Graph" },
          ].map(t => (
            <button key={t.k} onClick={() => setTab(t.k)}
              style={{
                background: tab === t.k ? C.surface2 : "transparent",
                color: tab === t.k ? C.text : C.mutedDeep,
                border: `1px solid ${tab === t.k ? C.borderLight : C.border}`,
                borderBottom: tab === t.k ? `2px solid ${C.sr}` : `1px solid ${tab === t.k ? C.borderLight : C.border}`,
                borderRadius: 5,
                padding: "6px 13px", fontSize: 12, cursor: "pointer",
                fontFamily: "inherit", fontWeight: tab === t.k ? 600 : 400,
                marginBottom: 4, transition: "all 100ms",
              }}>
              {t.label}
            </button>
          ))}
        </div>
      </div>

      {/* TABS */}
      {tab === "concepts" && (
        <ConceptsTab
          filtered={filtered} activeCluster={activeCluster} setActiveCluster={setActiveCluster}
          search={search} setSearch={setSearch}
          activeViews={activeViews} toggleView={toggleView}
          selectedId={selectedId} setSelectedId={setSelectedId} selected={selected}
        />
      )}
      {tab === "primitives" && <PrimitivesTab />}
      {tab === "systemtypes" && <SystemTypesTab jumpToConcept={jumpToConcept} />}
      {tab === "research" && <ResearchOpenSystemsTab />}
      {tab === "examples" && (
        <ExamplesTab exampleIdx={exampleIdx} setExampleIdx={setExampleIdx} jumpToConcept={jumpToConcept} />
      )}
      {tab === "methods" && (
        <MethodsTab methodIdx={methodIdx} setMethodIdx={setMethodIdx} />
      )}
      {tab === "practice" && (
        <PracticeTab jumpToConcept={jumpToConcept} />
      )}
      {tab === "agents" && (
        <AgentsTab setTab={setTab} />
      )}
      {tab === "frameworks" && (
        <FrameworksTab />
      )}
      {tab === "graph" && (
        <GraphTab setTab={setTab} />
      )}
    </div>
  );
}

// ─── CONCEPTS TAB ────────────────────────────────────────────────────────────
function ConceptsTab({ filtered, activeCluster, setActiveCluster, search, setSearch, activeViews, toggleView, selectedId, setSelectedId, selected }) {
  return (
    <>
      <div style={{
        background: C.surface, borderBottom: `1px solid ${C.border}`,
        padding: "12px 24px", display: "flex", flexDirection: "column", gap: 10,
      }}>
        <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
          <input value={search} onChange={e => setSearch(e.target.value)} placeholder="search concepts…"
            style={{
              background: C.surface2, color: C.text, border: `1px solid ${C.border}`,
              borderRadius: 6, padding: "6px 10px", fontSize: 12.5, minWidth: 220,
              fontFamily: "inherit", outline: "none",
            }} />
          <select value={activeCluster} onChange={e => setActiveCluster(e.target.value)}
            style={{
              background: C.surface2, color: C.text, border: `1px solid ${C.border}`,
              borderRadius: 6, padding: "6px 10px", fontSize: 12.5,
              fontFamily: "inherit", outline: "none", cursor: "pointer",
            }}>
            <option value="all">all clusters</option>
            {Object.keys(CLUSTERS).map(k => <option key={k} value={k}>{k}</option>)}
          </select>
          <span style={{ fontSize: 11, color: C.muted, fontFamily: "ui-monospace, monospace" }}>
            {filtered.length} / {CONCEPTS.length}
          </span>
        </div>
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap", alignItems: "center" }}>
          <span style={{ fontSize: 10.5, color: C.muted, marginRight: 6, fontFamily: "ui-monospace, monospace", letterSpacing: 0.3 }}>PRODUCTIVE</span>
          {Object.entries(FRAMEWORKS).filter(([, f]) => f.category === "productive").map(([key, fw]) => (
            <button key={key} onClick={() => toggleView(key)}
              style={{
                background: activeViews[key] ? `${fw.color}1f` : "transparent",
                color: activeViews[key] ? fw.color : C.mutedDeep,
                border: `1px solid ${activeViews[key] ? `${fw.color}55` : C.border}`,
                borderRadius: 5, padding: "4px 9px", fontSize: 10.5,
                fontFamily: "ui-monospace, monospace", letterSpacing: 0.3,
                cursor: "pointer", transition: "all 120ms",
                fontWeight: activeViews[key] ? 600 : 400,
              }}>
              {fw.short}
            </button>
          ))}
        </div>
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap", alignItems: "center" }}>
          <span style={{ fontSize: 10.5, color: C.muted, marginRight: 6, fontFamily: "ui-monospace, monospace", letterSpacing: 0.3 }}>METAPHYSICAL</span>
          {Object.entries(FRAMEWORKS).filter(([, f]) => f.category === "metaphysical").map(([key, fw]) => (
            <button key={key} onClick={() => toggleView(key)}
              style={{
                background: activeViews[key] ? `${fw.color}1f` : "transparent",
                color: activeViews[key] ? fw.color : C.mutedDeep,
                border: `1px solid ${activeViews[key] ? `${fw.color}55` : C.border}`,
                borderRadius: 5, padding: "4px 9px", fontSize: 10.5,
                fontFamily: "ui-monospace, monospace", letterSpacing: 0.3,
                cursor: "pointer", transition: "all 120ms",
                fontWeight: activeViews[key] ? 600 : 400,
              }}>
              {fw.short}
            </button>
          ))}
        </div>
      </div>

      <div style={{ minHeight: "calc(100vh - 220px)" }}>
        {filtered.map(c => {
          const cl = CLUSTERS[c.cluster];
          const isSelected = c.id === selectedId;
          return (
            <div key={c.id}>
              <div onClick={() => setSelectedId(isSelected ? null : c.id)}
                style={{
                  padding: "14px 24px",
                  borderBottom: isSelected ? "none" : `1px solid ${C.border}`,
                  cursor: "pointer", background: isSelected ? C.surface2 : "transparent",
                  borderLeft: `3px solid ${isSelected ? cl.color : "transparent"}`,
                  transition: "background 120ms",
                }}
                onMouseEnter={e => { if (!isSelected) e.currentTarget.style.background = C.surface; }}
                onMouseLeave={e => { if (!isSelected) e.currentTarget.style.background = "transparent"; }}>
                <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 5, flexWrap: "wrap" }}>
                  <div style={{
                    fontSize: 10, color: C.muted, fontFamily: "ui-monospace, monospace",
                    width: 16, textAlign: "center", userSelect: "none",
                  }}>{isSelected ? "▾" : "▸"}</div>
                  <div style={{ fontSize: 14.5, fontWeight: 600, color: C.text }}>{c.name}</div>
                  <div style={{
                    fontSize: 9.5, color: cl.color, background: `${cl.color}14`,
                    border: `1px solid ${cl.color}33`, padding: "1px 6px", borderRadius: 3,
                    letterSpacing: 0.4, fontFamily: "ui-monospace, monospace",
                    textTransform: "uppercase", fontWeight: 600,
                  }}>{cl.short}</div>
                  {c.decisions && c.decisions.length > 0 && (
                    <div style={{
                      fontSize: 9.5, color: C.decision, background: `${C.decision}14`,
                      border: `1px solid ${C.decision}33`, padding: "1px 6px",
                      borderRadius: 3, fontFamily: "ui-monospace, monospace",
                    }}>{c.decisions.length}d</div>
                  )}
                  {c.open && (
                    <div style={{
                      fontSize: 9.5, color: C.open, background: `${C.open}14`,
                      border: `1px solid ${C.open}33`, padding: "1px 6px",
                      borderRadius: 3, fontFamily: "ui-monospace, monospace",
                    }}>open</div>
                  )}
                  {c.opposingView && (
                    <div style={{
                      fontSize: 9.5, color: "#ef4444", background: "#ef444414",
                      border: "1px solid #ef444433", padding: "1px 6px",
                      borderRadius: 3, fontFamily: "ui-monospace, monospace",
                    }}>vs</div>
                  )}
                </div>
                <div style={{ fontSize: 12.5, color: C.textDim, lineHeight: 1.5, paddingLeft: 24 }}>{c.plain}</div>
              </div>

              {isSelected && (
                <ConceptDetail concept={c} activeViews={activeViews} setSelectedId={setSelectedId} />
              )}
            </div>
          );
        })}
      </div>
    </>
  );
}

// ─── CONCEPT DETAIL (accordion expansion) ─────────────────────────────────────
function ConceptDetail({ concept, activeViews, setSelectedId }) {
  const cl = CLUSTERS[concept.cluster];
  return (
    <div style={{
      padding: "20px 32px 28px 48px",
      background: C.surface2,
      borderLeft: `3px solid ${cl.color}`,
      borderBottom: `1px solid ${C.border}`,
    }}>
      <FrameworkBlock label="Structural Realism" short="SR" color={C.sr} bg={C.srBg} border={C.srBorder} content={concept.sr} isAnchor />
      <FrameworkBlock label="Information Theory" short="IT" color={C.it} bg={C.itBg} border={C.itBorder} content={concept.it} symbols={concept.itSym} isAnchor />

      {concept.views && Object.entries(concept.views).map(([key, content]) => {
        if (!activeViews[key] || !content) return null;
        const fw = FRAMEWORKS[key];
        return <FrameworkBlock key={key} label={fw.label} short={fw.short} color={fw.color} content={content} />;
      })}

      {concept.decisions && concept.decisions.length > 0 && (
        <div style={{
          marginTop: 18, padding: "12px 14px",
          background: `${C.decision}0a`, border: `1px solid ${C.decision}33`, borderRadius: 6,
        }}>
          <div style={{
            fontSize: 10.5, color: C.decision, fontFamily: "ui-monospace, monospace",
            letterSpacing: 0.5, marginBottom: 8, fontWeight: 600,
          }}>DECISION POINTS</div>
          {concept.decisions.map((d, i) => (
            <div key={i} style={{
              fontSize: 12.5, color: C.text, lineHeight: 1.55,
              paddingLeft: 14, position: "relative",
              marginBottom: i < concept.decisions.length - 1 ? 8 : 0,
            }}>
              <span style={{ position: "absolute", left: 0, color: C.decision }}>→</span>{d}
            </div>
          ))}
        </div>
      )}

      {concept.open && (
        <div style={{
          marginTop: 14, padding: "12px 14px",
          background: `${C.open}0a`, border: `1px solid ${C.open}33`, borderRadius: 6,
        }}>
          <div style={{
            fontSize: 10.5, color: C.open, fontFamily: "ui-monospace, monospace",
            letterSpacing: 0.5, marginBottom: 6, fontWeight: 600,
          }}>OPEN QUESTION</div>
          <div style={{ fontSize: 12.5, color: C.text, lineHeight: 1.55, fontStyle: "italic" }}>
            {concept.open}
          </div>
        </div>
      )}

      {concept.opposingView && (
        <div style={{
          marginTop: 14, padding: "12px 14px",
          background: "#ef44440a", border: "1px solid #ef444433", borderRadius: 6,
        }}>
          <div style={{
            fontSize: 10.5, color: "#ef4444", fontFamily: "ui-monospace, monospace",
            letterSpacing: 0.5, marginBottom: 6, fontWeight: 600,
          }}>OPPOSING VIEW</div>
          <div style={{ fontSize: 12.5, color: C.text, lineHeight: 1.55 }}>
            {concept.opposingView}
          </div>
        </div>
      )}

      {(concept.aiEx || concept.domEx) && (
        <div style={{ marginTop: 14, padding: "10px 14px", background: C.surface, border: `1px solid ${C.border}`, borderRadius: 6 }}>
          <div style={{ fontSize: 10.5, color: C.muted, fontFamily: "ui-monospace, monospace", letterSpacing: 0.5, marginBottom: 6, fontWeight: 600 }}>EXAMPLES</div>
          {concept.aiEx && (
            <div style={{ fontSize: 12, color: C.textDim, marginBottom: concept.domEx ? 6 : 0 }}>
              <span style={{ color: C.muted, fontFamily: "ui-monospace, monospace", fontSize: 10, marginRight: 6 }}>ML/AI</span>
              {concept.aiEx}
            </div>
          )}
          {concept.domEx && (
            <div style={{ fontSize: 12, color: C.textDim }}>
              <span style={{ color: C.muted, fontFamily: "ui-monospace, monospace", fontSize: 10, marginRight: 6 }}>SOC/HIST</span>
              {concept.domEx}
            </div>
          )}
        </div>
      )}

      {concept.related && concept.related.length > 0 && (
        <div style={{ marginTop: 18 }}>
          <div style={{
            fontSize: 10.5, color: C.muted, fontFamily: "ui-monospace, monospace",
            letterSpacing: 0.5, marginBottom: 8, fontWeight: 600,
          }}>RELATED</div>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
            {concept.related.map(r => {
              const target = CONCEPTS.find(c => c.id === r);
              if (!target) return null;
              const tcl = CLUSTERS[target.cluster];
              return (
                <button key={r} onClick={() => setSelectedId(r)}
                  style={{
                    background: "transparent", color: tcl.color,
                    border: `1px solid ${tcl.color}44`, borderRadius: 4,
                    padding: "3px 9px", fontSize: 11.5, cursor: "pointer",
                    fontFamily: "inherit", transition: "all 120ms",
                  }}
                  onMouseEnter={e => { e.currentTarget.style.background = `${tcl.color}14`; }}
                  onMouseLeave={e => { e.currentTarget.style.background = "transparent"; }}>
                  {target.name}
                </button>
              );
            })}
          </div>
        </div>
      )}

      <div style={{ marginTop: 20, textAlign: "right" }}>
        <button onClick={() => setSelectedId(null)}
          style={{
            background: "transparent", color: C.muted,
            border: `1px solid ${C.border}`, borderRadius: 5,
            padding: "5px 12px", fontSize: 11, cursor: "pointer",
            fontFamily: "ui-monospace, monospace", letterSpacing: 0.3,
          }}>close</button>
      </div>
    </div>
  );
}

// ─── EXAMPLES TAB ────────────────────────────────────────────────────────────
const READING_GRADE = {
  iso:      { label: "iso",      color: "#34d399", title: "mechanistic isomorphism — shared formal structure" },
  partial:  { label: "partial",  color: "#f59e0b", title: "partial correspondence — mechanisms map piecewise" },
  metaphor: { label: "metaphor", color: "#f472b6", title: "metaphor — vocabulary only, critique flagged" },
};

const TASMANIA_PRESETS = [
  { k: "baseline", label: "Baseline",                    a: 2.0, b: 0.30, logN: 3.0 },
  { k: "tasmania", label: "Tasmanian isolation (N ↓)",   a: 2.0, b: 0.30, logN: 2.18 },
  { k: "writing",  label: "Writing / printing (β ↑)",    a: 2.0, b: 0.60, logN: 2.18 },
];

function TasmaniaSim() {
  const [alpha, setAlpha] = useState(2.0);   // systematic copying loss (task difficulty)
  const [beta, setBeta]   = useState(0.30);  // dispersion of copying error (rare lucky overshoots)
  const [logN, setLogN]   = useState(3.0);   // log10 effective learner population
  const GAMMA = 0.5772156649;
  const N = Math.round(Math.pow(10, logN));
  const dz = (x) => -alpha + beta * (GAMMA + x);          // x = ln N
  const xCur = logN * Math.LN10;
  const dzCur = dz(xCur);
  const nStar = Math.exp(alpha / beta - GAMMA);

  const W = 640, H = 235, L = 50, R = 16, T = 16, B = 36;
  const xMin = Math.log(10), xMax = Math.log(100000);
  const y0 = dz(xMin), y1 = dz(xMax);
  const yMin = Math.min(y0, -0.6) * 1.12, yMax = Math.max(y1, 0.6) * 1.12;
  const px = (x) => L + ((x - xMin) / (xMax - xMin)) * (W - L - R);
  const py = (y) => T + ((yMax - y) / (yMax - yMin)) * (H - T - B);
  const xStar = Math.log(nStar);
  const growing = dzCur > 0;
  const fmtN = (n) => n >= 1000 ? `${Math.round(n / 100) / 10}k`.replace(".0k", "k") : `${Math.round(n)}`;

  const slider = (label, val, set, min, max, step, fmt) => (
    <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 8 }}>
      <div style={{ fontSize: 10.5, color: C.textDim, width: 250 }}>{label}</div>
      <input type="range" min={min} max={max} step={step} value={val}
        onChange={(e) => set(parseFloat(e.target.value))}
        style={{ flex: 1, accentColor: C.evo }} />
      <div style={{ fontSize: 11, color: C.text, fontFamily: "ui-monospace, monospace", width: 52, textAlign: "right" }}>{fmt(val)}</div>
    </div>
  );

  return (
    <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 8, padding: "18px 20px", marginBottom: 14 }}>
      <div style={{ fontSize: 13, fontWeight: 700, color: C.evo, marginBottom: 4, letterSpacing: 0.2 }}>
        Interactive — demography × fidelity bounds on cultural complexity
      </div>
      <div style={{ fontSize: 11.5, color: C.textDim, lineHeight: 1.55, marginBottom: 12 }}>
        Henrich (2004), simplified: <span style={{ fontFamily: "ui-monospace, monospace", color: C.text }}>Δz̄ = −α + β(γ + ln N)</span>.
        Learners imitate the most skilled visible model; α is systematic copying loss (task difficulty), β the dispersion of copying error
        (rare overshoots that beat the model), N the effective learner population. Mean skill grows only when lucky errors outpace degradation.
        Empirical support is mixed — see the EVO reading below.
      </div>
      <div style={{ display: "flex", gap: 6, flexWrap: "wrap", marginBottom: 12 }}>
        {TASMANIA_PRESETS.map(p => (
          <button key={p.k} onClick={() => { setAlpha(p.a); setBeta(p.b); setLogN(p.logN); }}
            style={{ background: C.surface2, color: C.textDim, border: `1px solid ${C.borderLight}`, borderRadius: 999,
              padding: "4px 11px", fontSize: 10.5, cursor: "pointer", fontFamily: "inherit" }}>
            {p.label}
          </button>
        ))}
      </div>
      <svg viewBox={`0 0 ${W} ${H}`} style={{ width: "100%", height: "auto", display: "block", marginBottom: 10 }}>
        {[10, 100, 1000, 10000, 100000].map(n => (
          <g key={n}>
            <line x1={px(Math.log(n))} y1={T} x2={px(Math.log(n))} y2={H - B} stroke={C.border} strokeWidth="1" />
            <text x={px(Math.log(n))} y={H - B + 15} fill={C.muted} fontSize="9.5" textAnchor="middle" fontFamily="ui-monospace, monospace">{fmtN(n)}</text>
          </g>
        ))}
        <text x={(L + W - R) / 2} y={H - 4} fill={C.muted} fontSize="9.5" textAnchor="middle">effective learner population N (log scale)</text>
        <text x={12} y={(T + H - B) / 2} fill={C.muted} fontSize="9.5" textAnchor="middle" transform={`rotate(-90 12 ${(T + H - B) / 2})`}>Δz̄ / generation</text>
        <line x1={L} y1={py(0)} x2={W - R} y2={py(0)} stroke={C.textDim} strokeWidth="1" strokeDasharray="4 4" />
        <text x={W - R - 4} y={py(0) - 5} fill={growing ? C.muted : "#f87171"} fontSize="9" textAnchor="end">toolkit decays below this line</text>
        <line x1={px(xMin)} y1={py(y0)} x2={px(xMax)} y2={py(y1)} stroke={C.evo} strokeWidth="2.2" />
        {xStar > xMin && xStar < xMax && (
          <g>
            <line x1={px(xStar)} y1={T} x2={px(xStar)} y2={H - B} stroke={C.accent} strokeWidth="1.4" strokeDasharray="3 3" />
            <text x={px(xStar) + 5} y={T + 11} fill={C.accent} fontSize="9.5" fontFamily="ui-monospace, monospace">N* ≈ {fmtN(nStar)}</text>
          </g>
        )}
        <circle cx={px(xCur)} cy={py(dzCur)} r="5.5" fill={growing ? "#34d399" : "#f87171"} stroke={C.bg} strokeWidth="1.5" />
      </svg>
      {slider("α — systematic copying loss (task difficulty)", alpha, setAlpha, 0.2, 3, 0.05, v => v.toFixed(2))}
      {slider("β — error dispersion (fidelity of lucky transmission)", beta, setBeta, 0.05, 1.5, 0.05, v => v.toFixed(2))}
      {slider("N — effective learner population", logN, setLogN, 1, 5, 0.02, () => fmtN(N))}
      <div style={{ background: C.surface2, border: `1px solid ${C.border}`, borderRadius: 6, padding: "9px 12px", fontSize: 12, color: C.text, lineHeight: 1.55, marginTop: 6 }}>
        At N = <b>{fmtN(N)}</b>: Δz̄ = <b style={{ color: growing ? "#34d399" : "#f87171", fontFamily: "ui-monospace, monospace" }}>{dzCur >= 0 ? "+" : ""}{dzCur.toFixed(2)}</b> per generation —
        toolkit complexity <b style={{ color: growing ? "#34d399" : "#f87171" }}>{growing ? "accumulates" : "decays"}</b>.
        Sustainability threshold N* ≈ <b style={{ fontFamily: "ui-monospace, monospace" }}>{fmtN(nStar)}</b> = e^(α/β − γ).
        Tasmania after isolation (~10 kya) sits left of N*: bone tools and fishing were lost with no one forgetting anything individually.
        Raising β (writing, printing, schooling) slides N* left — the same complexity becomes sustainable by fewer people.
      </div>
    </div>
  );
}

function ExamplesTab({ exampleIdx, setExampleIdx, jumpToConcept }) {
  const ex = EXAMPLES[exampleIdx];
  return (
    <div style={{ padding: "20px 24px 60px" }}>
      <div style={{ display: "flex", gap: 6, flexWrap: "wrap", marginBottom: 16 }}>
        {EXAMPLES.map((e, i) => (
          <button key={i} onClick={() => setExampleIdx(i)}
            style={{
              background: i === exampleIdx ? C.accent : C.surface,
              color: i === exampleIdx ? C.bg : C.textDim,
              border: `1px solid ${i === exampleIdx ? C.accent : C.border}`,
              borderRadius: 6, padding: "6px 11px", fontSize: 11.5,
              fontWeight: i === exampleIdx ? 600 : 400, cursor: "pointer",
              letterSpacing: 0.2, fontFamily: "inherit",
            }}>
            {String(i + 1).padStart(2, "0")} · {e.title}
          </button>
        ))}
      </div>

      <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 8, padding: "18px 20px", marginBottom: 14 }}>
        <div style={{ fontSize: 10.5, color: C.accent, fontWeight: 700, letterSpacing: 1, textTransform: "uppercase", marginBottom: 6 }}>
          {ex.domain}
        </div>
        <div style={{ fontSize: 20, fontWeight: 600, marginBottom: 12, letterSpacing: -0.3 }}>{ex.title}</div>
        <div style={{ fontSize: 13.5, color: C.text, lineHeight: 1.65, marginBottom: 12 }}>{ex.summary}</div>
        <div style={{ background: C.surface2, border: `1px solid ${C.border}`, borderRadius: 6, padding: "10px 12px", fontSize: 12.5, color: C.textDim, lineHeight: 1.6 }}>
          <span style={{ fontSize: 10, fontWeight: 700, color: C.muted, letterSpacing: 0.6, textTransform: "uppercase", marginRight: 6 }}>Setup</span>
          {ex.setup}
        </div>
      </div>

      {ex.cascade && (
        <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 8, padding: "18px 20px", marginBottom: 14 }}>
          <div style={{ fontSize: 13, fontWeight: 700, color: C.accent, marginBottom: 4, letterSpacing: 0.2 }}>The cascade</div>
          <div style={{ fontSize: 11.5, color: C.muted, marginBottom: 14 }}>Each stage: a coordination load that outruns existing institutions → an information technology that relieves it. Order carries the argument.</div>
          {ex.cascade.map((s, i) => (
            <div key={i} style={{ display: "flex", gap: 12, paddingBottom: 13, marginBottom: 13, borderBottom: i === ex.cascade.length - 1 ? "none" : `1px solid ${C.border}` }}>
              <div style={{ fontSize: 15, fontWeight: 700, color: C.mutedDeep, fontFamily: "ui-monospace, monospace", minWidth: 24 }}>{String(i + 1).padStart(2, "0")}</div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 13.5, fontWeight: 600, marginBottom: 5 }}>{s.stage}</div>
                <div style={{ fontSize: 12.5, color: C.text, lineHeight: 1.6, marginBottom: 4 }}>
                  <span style={{ fontSize: 9, fontWeight: 700, color: C.it, letterSpacing: 0.7, textTransform: "uppercase", marginRight: 6 }}>Load</span>{s.load}
                </div>
                <div style={{ fontSize: 12.5, color: C.text, lineHeight: 1.6, marginBottom: 4 }}>
                  <span style={{ fontSize: 9, fontWeight: 700, color: C.evo, letterSpacing: 0.7, textTransform: "uppercase", marginRight: 6 }}>Response</span>{s.response}
                </div>
                <div style={{ fontSize: 11.5, color: C.textDim, lineHeight: 1.55, fontStyle: "italic" }}>{s.note}</div>
              </div>
            </div>
          ))}
        </div>
      )}

      {ex.corrections && (
        <div style={{ background: C.surface, border: `1px solid #dc262655`, borderRadius: 8, padding: "18px 20px", marginBottom: 14 }}>
          <div style={{ fontSize: 13, fontWeight: 700, color: "#f87171", marginBottom: 4, letterSpacing: 0.2 }}>Folk story vs. evidence</div>
          <div style={{ fontSize: 11.5, color: C.muted, marginBottom: 14 }}>Falsifiability discipline: state the popular claim, test it, keep only what survives.</div>
          {ex.corrections.map((c, i) => (
            <div key={i} style={{ paddingBottom: 14, marginBottom: 14, borderBottom: i === ex.corrections.length - 1 ? "none" : `1px solid ${C.border}` }}>
              <div style={{ fontSize: 12.5, color: C.textDim, fontStyle: "italic", marginBottom: 5 }}>"{c.folk}"</div>
              <div style={{ fontSize: 11, fontWeight: 700, color: "#f87171", letterSpacing: 0.4, textTransform: "uppercase", marginBottom: 6 }}>✗ {c.verdict}</div>
              <div style={{ fontSize: 12.5, color: C.text, lineHeight: 1.6, marginBottom: 8 }}>{c.evidence}</div>
              <div style={{ background: "#34d3990d", border: `1px solid #34d39933`, borderRadius: 6, padding: "8px 11px", fontSize: 12, color: C.text, lineHeight: 1.55 }}>
                <span style={{ fontSize: 9, fontWeight: 700, color: "#34d399", letterSpacing: 0.7, textTransform: "uppercase", marginRight: 6 }}>What survives</span>{c.survives}
              </div>
            </div>
          ))}
        </div>
      )}

      {ex.interactive === "demography" && <TasmaniaSim />}

      <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 8, padding: "18px 20px", marginBottom: 14 }}>
        <div style={{ fontSize: 13, fontWeight: 700, color: C.accent, marginBottom: 14, letterSpacing: 0.2 }}>
          How the concepts manifest
        </div>
        {ex.mappings.map((m, i) => {
          const target = CONCEPTS.find(c => c.name === m.concept);
          const cl = target ? CLUSTERS[target.cluster] : { color: C.muted, short: "?" };
          return (
            <div key={i} style={{
              paddingBottom: 14, marginBottom: 14,
              borderBottom: i === ex.mappings.length - 1 ? "none" : `1px solid ${C.border}`,
            }}>
              <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 6, flexWrap: "wrap" }}>
                <button onClick={() => target && jumpToConcept(target.id)}
                  disabled={!target}
                  style={{
                    background: "transparent",
                    border: `1px solid ${cl.color}44`,
                    color: cl.color, fontSize: 12,
                    padding: "3px 9px", borderRadius: 999,
                    cursor: target ? "pointer" : "default",
                    fontWeight: 600, fontFamily: "inherit",
                  }}>→ {m.concept}</button>
                <span style={{ fontSize: 9, color: cl.color, fontWeight: 700, letterSpacing: 0.6, fontFamily: "ui-monospace, monospace" }}>
                  {cl.short}
                </span>
              </div>
              <div style={{ fontSize: 13, color: C.text, lineHeight: 1.6 }}>{m.how}</div>
            </div>
          );
        })}
      </div>

      {ex.frameworkReadings && (
        <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 8, padding: "18px 20px", marginBottom: 14 }}>
          <div style={{ fontSize: 13, fontWeight: 700, color: C.accent, marginBottom: 4, letterSpacing: 0.2 }}>Framework readings</div>
          <div style={{ fontSize: 11.5, color: C.muted, marginBottom: 14 }}>
            Same phenomenon, seven lenses — each edge graded by the atlas isomorphism standard:{" "}
            {Object.values(READING_GRADE).map((g, i) => (
              <span key={i} title={g.title} style={{ color: g.color, fontWeight: 600, marginRight: 8 }}>● {g.label}</span>
            ))}
          </div>
          {ex.frameworkReadings.map((r, i) => {
            const fw = FRAMEWORKS[r.fw] || { label: r.fw, short: "?", color: C.muted };
            const g = READING_GRADE[r.grade] || READING_GRADE.partial;
            return (
              <div key={i} style={{ paddingBottom: 13, marginBottom: 13, borderBottom: i === ex.frameworkReadings.length - 1 ? "none" : `1px solid ${C.border}` }}>
                <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 6, flexWrap: "wrap" }}>
                  <span style={{ border: `1px solid ${fw.color}55`, color: fw.color, fontSize: 12, padding: "3px 9px", borderRadius: 999, fontWeight: 600 }}>{fw.label}</span>
                  <span title={g.title} style={{ fontSize: 9.5, fontWeight: 700, color: g.color, letterSpacing: 0.6, border: `1px solid ${g.color}44`, borderRadius: 999, padding: "2px 8px", fontFamily: "ui-monospace, monospace" }}>{g.label}</span>
                </div>
                <div style={{ fontSize: 13, color: C.text, lineHeight: 1.6 }}>{r.how}</div>
              </div>
            );
          })}
        </div>
      )}

      <div style={{ background: `${C.accent}10`, border: `1px solid ${C.accent}44`, borderRadius: 8, padding: "14px 18px" }}>
        <div style={{ fontSize: 10, fontWeight: 700, color: C.accent, letterSpacing: 0.7, textTransform: "uppercase", marginBottom: 8 }}>Lesson</div>
        <div style={{ fontSize: 13.5, lineHeight: 1.65, color: C.text }}>{ex.lesson}</div>
      </div>
    </div>
  );
}

// ─── METHODS TAB ─────────────────────────────────────────────────────────────
function MethodsTab({ methodIdx, setMethodIdx }) {
  const m = METHODS[methodIdx];
  return (
    <div style={{ display: "grid", gridTemplateColumns: "260px 1fr", minHeight: "calc(100vh - 220px)" }}>
      <div style={{ borderRight: `1px solid ${C.border}`, overflowY: "auto" }}>
        {METHODS.map((method, i) => (
          <div key={method.id} onClick={() => setMethodIdx(i)}
            style={{
              padding: "12px 18px", borderBottom: `1px solid ${C.border}`,
              cursor: "pointer", background: i === methodIdx ? C.surface2 : "transparent",
              borderLeft: `3px solid ${i === methodIdx ? C.accent : "transparent"}`,
            }}>
            <div style={{ fontSize: 10, color: C.muted, fontFamily: "ui-monospace, monospace", letterSpacing: 0.4, marginBottom: 2 }}>
              {String(i + 1).padStart(2, "0")}
            </div>
            <div style={{ fontSize: 13, fontWeight: i === methodIdx ? 600 : 500, color: i === methodIdx ? C.text : C.textDim, lineHeight: 1.4 }}>
              {method.title}
            </div>
          </div>
        ))}
      </div>
      <div style={{ overflowY: "auto", padding: "24px 32px 60px", maxWidth: 900 }}>
        <div style={{ fontSize: 11, color: C.accent, fontWeight: 700, letterSpacing: 1, textTransform: "uppercase", marginBottom: 8 }}>
          Methodology
        </div>
        <div style={{ fontSize: 22, fontWeight: 600, marginBottom: 14, letterSpacing: -0.3 }}>{m.title}</div>

        {m.intro && (
          <div style={{ fontSize: 13.5, color: C.textDim, lineHeight: 1.65, marginBottom: 24, fontStyle: "italic" }}>
            <Inline text={m.intro} />
          </div>
        )}

        {m.sections && m.sections.map((s, i) => (
          <MethodSection key={i} section={s} />
        ))}

        {m.closing && (
          <div style={{
            marginTop: 24, padding: "12px 14px",
            background: `${C.accent}0a`, border: `1px solid ${C.accent}33`,
            borderRadius: 6, fontSize: 13, color: C.text, lineHeight: 1.6,
          }}>
            <Inline text={m.closing} />
          </div>
        )}
      </div>
    </div>
  );
}

function MethodSection({ section }) {
  return (
    <div style={{ marginBottom: 22 }}>
      <div style={{
        fontSize: 13, fontWeight: 700, color: C.text,
        marginBottom: 8, paddingBottom: 6,
        borderBottom: `1px solid ${C.border}`,
      }}>
        {section.heading}
      </div>
      {section.intro && (
        <div style={{ fontSize: 12.5, color: C.textDim, lineHeight: 1.6, marginBottom: 10, fontStyle: "italic" }}>
          <Inline text={section.intro} />
        </div>
      )}
      {section.bullets && section.bullets.map((b, i) => (
        <div key={i} style={{
          fontSize: 13, color: C.text, lineHeight: 1.6,
          paddingLeft: 16, position: "relative",
          marginBottom: i < section.bullets.length - 1 ? 6 : 0,
        }}>
          <span style={{ position: "absolute", left: 0, color: C.muted }}>•</span>
          <Inline text={b} />
        </div>
      ))}
      {section.formulas && section.formulas.length > 0 && (
        <FormulaBlock formulas={section.formulas} />
      )}
    </div>
  );
}

// Parse a formula string into React elements with proper <sub>/<sup>.
// Handles: _{...} ^{...} ^(...) for braced; _xyz ^xyz for unbraced sequences.
function renderFormula(str) {
  if (!str) return null;
  // Subscriptable / superscriptable characters: word chars + Greek + math symbols
  // Note: this is applied after braced/parened forms are tokenized
  const SUB_CHARS = "A-Za-z0-9μπσϕφλΛΦΣΩαβγδεζηθικλνξορτυχψω*'+\\-";
  // Build a single regex matching any of: _{...}, ^{...}, ^(...), _word, ^word
  const re = new RegExp(
    "_\\{([^}]+)\\}|" +     // _{...} → group 1
    "\\^\\{([^}]+)\\}|" +   // ^{...} → group 2
    "\\^\\(([^)]+)\\)|" +   // ^(...) → group 3
    "_([" + SUB_CHARS + "]+)|" +     // _word → group 4
    "\\^([" + SUB_CHARS + "]+)",    // ^word → group 5
    "g"
  );
  const out = [];
  let last = 0;
  let m;
  let key = 0;
  while ((m = re.exec(str)) !== null) {
    if (m.index > last) {
      out.push(str.substring(last, m.index));
    }
    if (m[1] !== undefined) {
      out.push(<sub key={key++} style={{ fontSize: "0.78em" }}>{m[1]}</sub>);
    } else if (m[2] !== undefined) {
      out.push(<sup key={key++} style={{ fontSize: "0.78em" }}>{m[2]}</sup>);
    } else if (m[3] !== undefined) {
      out.push(<sup key={key++} style={{ fontSize: "0.78em" }}>{m[3]}</sup>);
    } else if (m[4] !== undefined) {
      out.push(<sub key={key++} style={{ fontSize: "0.78em" }}>{m[4]}</sub>);
    } else if (m[5] !== undefined) {
      out.push(<sup key={key++} style={{ fontSize: "0.78em" }}>{m[5]}</sup>);
    }
    last = re.lastIndex;
  }
  if (last < str.length) out.push(str.substring(last));
  return out;
}

function FormulaBlock({ formulas }) {
  return (
    <div style={{
      marginTop: 10,
      background: C.surface2, border: `1px solid ${C.border}`,
      borderRadius: 5, padding: "10px 12px",
    }}>
      {formulas.map((entry, i) => (
        <div key={i} style={{
          display: "grid", gridTemplateColumns: "minmax(0, 1.3fr) minmax(0, 1fr)",
          gap: 14, alignItems: "baseline",
          paddingBottom: i < formulas.length - 1 ? 7 : 0,
          marginBottom: i < formulas.length - 1 ? 7 : 0,
          borderBottom: i < formulas.length - 1 ? `1px solid ${C.border}` : "none",
        }}>
          <code style={{
            fontSize: 12.5, color: C.text,
            fontFamily: "ui-monospace, 'IBM Plex Mono', monospace",
            whiteSpace: "pre-wrap", wordBreak: "break-word",
            lineHeight: 1.7,
          }}>{renderFormula(entry.f)}</code>
          <span style={{ fontSize: 11, color: C.muted, fontStyle: "italic" }}>
            {entry.label}
          </span>
        </div>
      ))}
    </div>
  );
}

// Render inline **bold** within prose; everything else passes through.
function Inline({ text }) {
  if (!text) return null;
  const parts = text.split(/(\*\*[^*]+\*\*)/g);
  return (
    <>
      {parts.map((p, i) =>
        p.startsWith("**") && p.endsWith("**")
          ? <strong key={i} style={{ color: C.text, fontWeight: 600 }}>{p.slice(2, -2)}</strong>
          : <span key={i}>{p}</span>
      )}
    </>
  );
}

// ─── PRACTICE TAB ────────────────────────────────────────────────────────────
function PracticeTab({ jumpToConcept }) {
  return (
    <div style={{ padding: "24px 32px 60px", maxWidth: 960, margin: "0 auto" }}>
      <div style={{ marginBottom: 28 }}>
        <div style={{ fontSize: 16, fontWeight: 600, marginBottom: 6 }}>Exercises</div>
        <div style={{ fontSize: 12.5, color: C.textDim, lineHeight: 1.6, marginBottom: 14 }}>
          Apply the framework to real systems. Forced application reveals what each concept actually does — and exposes which ones you don't yet understand.
        </div>
        {EXERCISES.map((ex, i) => (
          <ExerciseCard key={i} ex={ex} />
        ))}
      </div>

      <div style={{ marginBottom: 28 }}>
        <div style={{ fontSize: 16, fontWeight: 600, marginBottom: 6 }}>Learning Path</div>
        <div style={{ fontSize: 12.5, color: C.textDim, lineHeight: 1.6, marginBottom: 14 }}>
          A possible sequence. Adjust based on your background. The first two weeks are essential; later weeks branch.
        </div>
        {LEARNING_PATH.map((p, i) => (
          <div key={i} style={{
            background: C.surface, border: `1px solid ${C.border}`, borderRadius: 6,
            padding: "12px 16px", marginBottom: 8,
          }}>
            <div style={{ display: "flex", alignItems: "baseline", gap: 12, marginBottom: 4, flexWrap: "wrap" }}>
              <div style={{
                fontSize: 10, color: C.accent, fontFamily: "ui-monospace, monospace",
                letterSpacing: 0.5, fontWeight: 700,
                background: `${C.accent}14`, border: `1px solid ${C.accent}33`,
                padding: "1px 7px", borderRadius: 3,
              }}>{p.phase}</div>
              <div style={{ fontSize: 13.5, fontWeight: 600, color: C.text }}>{p.title}</div>
            </div>
            <div style={{ fontSize: 12.5, color: C.textDim, lineHeight: 1.6 }}>{p.text}</div>
          </div>
        ))}
      </div>

      <div>
        <div style={{ fontSize: 16, fontWeight: 600, marginBottom: 6 }}>Essential Books</div>
        <div style={{ fontSize: 12.5, color: C.textDim, lineHeight: 1.6, marginBottom: 14 }}>
          Curated by topic. The metaphysics section is new — most working scientists never read these but they shape every framework you use.
        </div>
        <BooksList />
      </div>
    </div>
  );
}

function ExerciseCard({ ex }) {
  return (
    <div style={{
      background: C.surface, border: `1px solid ${C.border}`,
      borderLeft: `3px solid ${C.accent}`, borderRadius: 6,
      padding: "14px 18px", marginBottom: 12,
    }}>
      <div style={{ fontSize: 13.5, fontWeight: 600, color: C.text, marginBottom: 6 }}>{ex.title}</div>
      {ex.goal && (
        <div style={{ fontSize: 12.5, color: C.textDim, marginBottom: 10, fontStyle: "italic" }}>
          <span style={{ color: C.muted, fontFamily: "ui-monospace, monospace", fontSize: 10, marginRight: 6 }}>GOAL</span>
          {ex.goal}
        </div>
      )}
      {ex.steps && (
        <ol style={{ margin: "0 0 10px 0", paddingLeft: 22, color: C.text }}>
          {ex.steps.map((s, i) => (
            <li key={i} style={{ fontSize: 12.5, lineHeight: 1.6, marginBottom: 4 }}>
              <Inline text={s} />
            </li>
          ))}
        </ol>
      )}
      {ex.leverage_ladder && (
        <div style={{
          marginTop: 8, marginBottom: 10,
          background: C.surface2, border: `1px solid ${C.border}`,
          borderRadius: 4, padding: "10px 12px",
        }}>
          <div style={{
            fontSize: 10, color: C.muted, fontFamily: "ui-monospace, monospace",
            letterSpacing: 0.5, fontWeight: 700, marginBottom: 6,
          }}>LEVERAGE LADDER (Meadows)</div>
          {ex.leverage_ladder.map((l, i) => (
            <code key={i} style={{
              display: "block", fontSize: 11.5, color: C.text,
              fontFamily: "ui-monospace, 'IBM Plex Mono', monospace",
              lineHeight: 1.7,
            }}>{l}</code>
          ))}
        </div>
      )}
      {ex.framework_checklist && (
        <div style={{
          marginTop: 8, marginBottom: 10,
          background: C.surface2, border: `1px solid ${C.border}`,
          borderRadius: 4, padding: "10px 12px",
        }}>
          <div style={{
            fontSize: 10, color: C.muted, fontFamily: "ui-monospace, monospace",
            letterSpacing: 0.5, fontWeight: 700, marginBottom: 6,
          }}>FRAMEWORK CHECKLIST</div>
          {ex.framework_checklist.map((c, i) => (
            <div key={i} style={{
              fontSize: 12, color: C.textDim, lineHeight: 1.55,
              paddingLeft: 12, position: "relative",
              marginBottom: i < ex.framework_checklist.length - 1 ? 4 : 0,
            }}>
              <span style={{ position: "absolute", left: 0, color: C.muted }}>·</span>
              <Inline text={c} />
            </div>
          ))}
        </div>
      )}
      {ex.insight && (
        <div style={{
          marginTop: 8, fontSize: 12, color: C.textDim,
          lineHeight: 1.55, fontStyle: "italic",
          paddingTop: 8, borderTop: `1px solid ${C.border}`,
        }}>
          <span style={{ color: C.accent, fontFamily: "ui-monospace, monospace", fontSize: 10, marginRight: 6, fontStyle: "normal" }}>INSIGHT</span>
          <Inline text={ex.insight} />
        </div>
      )}
    </div>
  );
}

const BOOK_CATEGORIES = {
  foundation:  "Foundation",
  information: "Information Theory",
  causation:   "Causal Inference",
  scale:       "Multi-scale & Emergence",
  evolution:   "Evolution",
  networks:    "Networks",
  thermo:      "Thermodynamics",
  aif:         "Active Inference",
  assembly:    "Assembly Theory",
  metaphysics: "Metaphysical Systems",
};

function BooksList() {
  // Group by category, preserving order
  const groups = {};
  for (const b of BOOKS) {
    const k = b.category || "foundation";
    (groups[k] = groups[k] || []).push(b);
  }
  return (
    <div>
      {Object.keys(BOOK_CATEGORIES).filter(k => groups[k]).map(k => (
        <div key={k} style={{ marginBottom: 16 }}>
          <div style={{
            fontSize: 10.5, color: C.muted, fontFamily: "ui-monospace, monospace",
            letterSpacing: 0.5, fontWeight: 700, marginBottom: 6,
          }}>{BOOK_CATEGORIES[k].toUpperCase()}</div>
          {groups[k].map((b, i) => (
            <div key={i} style={{
              background: C.surface, border: `1px solid ${C.border}`,
              borderRadius: 5, padding: "8px 12px", marginBottom: 5,
            }}>
              <div style={{ display: "flex", alignItems: "baseline", gap: 8, flexWrap: "wrap" }}>
                <span style={{ fontSize: 12.5, fontWeight: 600, color: C.text }}>{b.name}</span>
                <span style={{ fontSize: 11.5, color: C.textDim }}>· {b.author}</span>
                <span style={{ fontSize: 11, color: C.muted, fontFamily: "ui-monospace, monospace" }}>{b.year}</span>
              </div>
              <div style={{ fontSize: 11.5, color: C.muted, marginTop: 3, fontStyle: "italic" }}>{b.note}</div>
            </div>
          ))}
        </div>
      ))}
    </div>
  );
}

// ─── AGENTS TAB ──────────────────────────────────────────────────────────────
function AgentsTab({ setTab }) {
  const [section, setSection] = useState("intro");

  const sections = [
    { k: "intro",       label: "Why this tab" },
    { k: "definitions", label: "Defining the agent" },
    { k: "grid",        label: "Substrate × framework" },
    { k: "proposals",   label: "Research proposals" },
    { k: "comparative", label: "Comparative dimension" },
    { k: "critiques",   label: "Critiques & caveats" },
  ];

  return (
    <div style={{ display: "grid", gridTemplateColumns: "240px 1fr", minHeight: "calc(100vh - 220px)" }}>
      {/* Sidebar */}
      <div style={{ borderRight: `1px solid ${C.border}`, padding: "16px 0" }}>
        <div style={{
          fontSize: 10, color: C.muted, fontFamily: "ui-monospace, monospace",
          letterSpacing: 0.6, padding: "0 18px 8px", fontWeight: 700,
        }}>
          AGENTIC SYSTEMS
        </div>
        {sections.map((s, i) => (
          <div key={s.k} onClick={() => setSection(s.k)}
            style={{
              padding: "10px 18px", cursor: "pointer",
              background: section === s.k ? C.surface2 : "transparent",
              borderLeft: `3px solid ${section === s.k ? C.accent : "transparent"}`,
              fontSize: 12.5, fontWeight: section === s.k ? 600 : 500,
              color: section === s.k ? C.text : C.textDim,
            }}>
            <span style={{ color: C.muted, marginRight: 8, fontFamily: "ui-monospace, monospace", fontSize: 10 }}>
              {String(i + 1).padStart(2, "0")}
            </span>
            {s.label}
          </div>
        ))}

        <div style={{ marginTop: 24, padding: "12px 18px", borderTop: `1px solid ${C.border}` }}>
          <div style={{
            fontSize: 10, color: C.muted, fontFamily: "ui-monospace, monospace",
            letterSpacing: 0.4, marginBottom: 6,
          }}>
            JUMP TO METHOD
          </div>
          <div onClick={() => setTab("methods")} style={{
            fontSize: 12, color: C.accent, cursor: "pointer",
            textDecoration: "underline", textDecorationStyle: "dotted",
          }}>
            Cross-substrate workflow →
          </div>
        </div>
      </div>

      {/* Content */}
      <div style={{ overflowY: "auto", padding: "24px 32px 60px", maxWidth: 1000 }}>
        {section === "intro" && <AgentsIntro />}
        {section === "definitions" && <AgentsDefinitions />}
        {section === "grid" && <AgentsGrid />}
        {section === "proposals" && <AgentsProposals />}
        {section === "comparative" && <AgentsComparative />}
        {section === "critiques" && <AgentsCritiques />}
      </div>
    </div>
  );
}

function AgentsIntro() {
  return (
    <>
      <div style={{ fontSize: 11, color: C.accent, fontWeight: 700, letterSpacing: 1, textTransform: "uppercase", marginBottom: 8 }}>
        Agentic Systems
      </div>
      <div style={{ fontSize: 22, fontWeight: 600, marginBottom: 14, letterSpacing: -0.3 }}>
        Agents as systems — and as research instruments
      </div>
      <div style={{ fontSize: 13.5, color: C.textDim, lineHeight: 1.7, marginBottom: 22, fontStyle: "italic" }}>
        Agency is currently over-defined and under-converged. Eight formal frameworks give materially different "minimal agent" definitions. None has decisively won. This tab maps where they agree, where they fight, and what's testable across three substrates: brain functional areas, societal agents, and designed/AI agents.
      </div>

      <div style={{
        background: C.surface, border: `1px solid ${C.border}`,
        borderRadius: 8, padding: "16px 20px", marginBottom: 18,
      }}>
        <div style={{ fontSize: 13, fontWeight: 700, marginBottom: 10 }}>The central claim</div>
        <div style={{ fontSize: 13, color: C.text, lineHeight: 1.65, marginBottom: 8 }}>
          Each framework has been applied to <strong>at least one</strong> of these substrates. Computational mechanics → EEG microstates and financial markets. Active inference → brain regions and now LLMs. Causal emergence → boolean networks, brains, Game of Life, flocking boids. But <strong>no published study runs the same operationalisation across all three substrates</strong>.
        </div>
        <div style={{ fontSize: 13, color: C.text, lineHeight: 1.65 }}>
          That is the productive open methodological niche. It is also the angle on which a single researcher with the right computational toolkit can do publishable work without competing against full labs.
        </div>
      </div>

      <div style={{ fontSize: 13, fontWeight: 700, marginBottom: 8, marginTop: 24 }}>The minimal-agent consensus</div>
      <div style={{ fontSize: 12.5, color: C.text, lineHeight: 1.7, marginBottom: 12 }}>
        Across the eight frameworks, the closest thing to a definitional intersection is:
      </div>
      <div style={{
        background: `${C.accent}10`,
        border: `1px solid ${C.accent}55`,
        borderLeft: `4px solid ${C.accent}`,
        borderRadius: 6, padding: "14px 18px", marginBottom: 16,
        fontSize: 13, lineHeight: 1.6,
      }}>
        <em>A stochastic process with a partition into system / environment such that the system's next state retains conditional dependence on its own past given the environment</em> — i.e. Krakauer's <code style={{ fontFamily: "ui-monospace, monospace", fontSize: 13, color: C.accent }}>{renderFormula("A* = I(S_{n+1}; S_n | E_n) > 0")}</code>.
      </div>
      <div style={{ fontSize: 12.5, color: C.textDim, lineHeight: 1.65 }}>
        This is a strict subset of "things with Markov blankets" — many MB systems are driven rather than organismal individuals. Frameworks then disagree about whether real agency requires <em>normativity</em> (enactivism, semantic information), <em>causal supremacy at a coarse scale</em> (Hoel), or <em>replication / copy-number</em> (assembly theory).
      </div>

      <div style={{ fontSize: 13, fontWeight: 700, marginBottom: 8, marginTop: 24 }}>How to use this tab</div>
      <div style={{ fontSize: 12.5, color: C.text, lineHeight: 1.7 }}>
        Use <strong>Defining the agent</strong> to compare the eight formal definitions side-by-side. Use <strong>Substrate × framework</strong> to see where work has been done and where the gaps are. Use <strong>Research proposals</strong> for ten concrete projects with hypotheses and falsification criteria — start with the three marked "priority" if you want a clean, low-risk entry point. <strong>Comparative dimension</strong> covers what's shared and divergent across substrate pairs. <strong>Critiques</strong> is the honest accounting of where the frameworks fail or are contested — read this before designing any project.
      </div>

      <div style={{ fontSize: 13, fontWeight: 700, marginBottom: 8, marginTop: 24 }}>Worked case studies (in the Examples tab)</div>
      <div style={{ fontSize: 12.5, color: C.text, lineHeight: 1.7, marginBottom: 6 }}>
        Two extended applications where the frameworks here meet real domains:
      </div>
      <div style={{
        background: C.surface, border: `1px solid ${C.border}`,
        borderLeft: `3px solid ${C.accent}`,
        borderRadius: 5, padding: "10px 14px", marginBottom: 8,
        fontSize: 12.5, color: C.text, lineHeight: 1.6,
      }}>
        <strong>Building Agentic AI Systems</strong> — applied design domain (Claude Code, AutoGen, multi-agent LLMs). Conant-Ashby, requisite variety, information bottleneck, Krakauer A*, causal emergence, statistical complexity all become engineering tools, not just descriptive concepts. Includes the open question: when does a multi-agent LLM system cross the individuality threshold?
      </div>
      <div style={{
        background: C.surface, border: `1px solid ${C.border}`,
        borderLeft: `3px solid ${C.accent}`,
        borderRadius: 5, padding: "10px 14px",
        fontSize: 12.5, color: C.text, lineHeight: 1.6,
      }}>
        <strong>Realism vs Liberalism vs Constructivism in International Politics</strong> — the agency-vs-structure debate in IR theory mapped onto the atlas's frameworks. Structural realism aligns with substance metaphysics; constructivism (Wendt, via Bhaskar's critical realism) is the natural complexity-friendly position. Includes empirical proposals: causal emergence on Correlates-of-War data, ε-machines of system dynamics, network analysis of alliance structure.
      </div>
    </>
  );
}

function AgentsDefinitions() {
  return (
    <>
      <div style={{ fontSize: 11, color: C.accent, fontWeight: 700, letterSpacing: 1, textTransform: "uppercase", marginBottom: 8 }}>
        Agentic Systems · Definitions
      </div>
      <div style={{ fontSize: 22, fontWeight: 600, marginBottom: 14, letterSpacing: -0.3 }}>
        How each framework formally defines an agent
      </div>
      <div style={{ fontSize: 13, color: C.textDim, lineHeight: 1.65, marginBottom: 24, fontStyle: "italic" }}>
        Ten formal definitions, ranked roughly from most ambitious (FEP) to most operationally clean (Krakauer's A*). Each card shows the minimal definition, the formal core, how it's operationalised on data, current status, and what kind of property it requires.
      </div>

      {AGENT_DEFINITIONS.map((d, i) => {
        const fw = FRAMEWORKS[d.fw] || { color: C.muted, short: d.fw.toUpperCase() };
        return (
          <div key={i} style={{
            marginBottom: 14,
            background: C.surface, border: `1px solid ${C.border}`,
            borderLeft: `4px solid ${fw.color}`, borderRadius: 6,
            padding: "14px 18px",
          }}>
            <div style={{ display: "flex", alignItems: "baseline", gap: 12, marginBottom: 10 }}>
              <div style={{
                fontSize: 10.5, color: fw.color, fontFamily: "ui-monospace, monospace",
                letterSpacing: 0.5, fontWeight: 700,
                background: `${fw.color}14`, border: `1px solid ${fw.color}33`,
                padding: "2px 7px", borderRadius: 3,
              }}>{fw.short}</div>
              <div style={{ fontSize: 14.5, fontWeight: 600 }}>{d.label}</div>
            </div>

            <AgentDefField label="MINIMAL" content={d.minimal} color={fw.color} />
            <AgentDefField label="FORMAL CORE" content={d.formal} color={fw.color} mono />
            <AgentDefField label="OPERATIONALISATION" content={d.operational} color={fw.color} />
            <AgentDefField label="STATUS" content={d.status} color={C.open} italic />

            {/* Requirements summary */}
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 12 }}>
              {Object.entries({
                boundary: "boundary",
                predicts: "predicts env.",
                normativity: "normativity",
                replication: "replication",
                coarseGrain: "coarse-grain primary",
                code: "code available",
              }).map(([key, label]) => (
                <span key={key} style={{
                  fontSize: 10.5,
                  color: d.requires[key] ? C.text : C.mutedDeep,
                  background: d.requires[key] ? `${fw.color}1a` : "transparent",
                  border: `1px solid ${d.requires[key] ? `${fw.color}66` : C.border}`,
                  padding: "2px 8px", borderRadius: 10,
                  fontFamily: "ui-monospace, monospace",
                  textDecoration: d.requires[key] ? "none" : "line-through",
                  opacity: d.requires[key] ? 1 : 0.5,
                }}>{label}</span>
              ))}
            </div>
          </div>
        );
      })}

      <div style={{
        marginTop: 18, padding: "12px 16px",
        background: `${C.accent}0a`, border: `1px solid ${C.accent}33`,
        borderRadius: 6, fontSize: 12.5, color: C.text, lineHeight: 1.65,
      }}>
        <strong>The convergence-divergence pattern.</strong> Frameworks converge on requiring a system / environment partition and forward-temporal self-prediction. They diverge sharply on whether agency requires normativity (enactivism, semantic info), causal coarse-grain supremacy (Hoel), or replication / copy-number (assembly theory). The cleanest cross-framework measure for empirical work is Krakauer's A* — it's portable, operational, and has the lightest metaphysical commitments.
      </div>
    </>
  );
}

function AgentDefField({ label, content, color, mono, italic }) {
  return (
    <div style={{ marginBottom: 8 }}>
      <div style={{
        fontSize: 9.5, color, fontFamily: "ui-monospace, monospace",
        letterSpacing: 0.6, fontWeight: 700, marginBottom: 3,
      }}>
        {label}
      </div>
      <div style={{
        fontSize: 12.5, color: C.text, lineHeight: mono ? 1.75 : 1.6,
        fontFamily: mono ? "ui-monospace, 'IBM Plex Mono', monospace" : "inherit",
        fontStyle: italic ? "italic" : "normal",
      }}>
        {mono ? renderFormula(content) : content}
      </div>
    </div>
  );
}

function AgentsGrid() {
  const substrates = [
    { k: "brain",   label: "Brain functional areas", color: "#ec4899" },
    { k: "society", label: "Societal agents",        color: "#f97316" },
    { k: "ai",      label: "Designed / AI agents",   color: "#06b6d4" },
  ];

  // Group cells by framework, then substrate
  const byFw = {};
  for (const cell of AGENT_SUBSTRATE_GRID) {
    (byFw[cell.fw] = byFw[cell.fw] || {})[cell.substrate] = cell;
  }

  const statusColor = (status) => {
    if (status === "done") return "#10b981";
    if (status === "partial") return "#f59e0b";
    return "#94a3b8";
  };
  const statusLabel = (status) => {
    if (status === "done") return "DONE";
    if (status === "partial") return "PARTIAL";
    return "OPEN";
  };

  return (
    <>
      <div style={{ fontSize: 11, color: C.accent, fontWeight: 700, letterSpacing: 1, textTransform: "uppercase", marginBottom: 8 }}>
        Agentic Systems · Substrate Grid
      </div>
      <div style={{ fontSize: 22, fontWeight: 600, marginBottom: 14, letterSpacing: -0.3 }}>
        Framework applications across the three substrates
      </div>
      <div style={{ fontSize: 13, color: C.textDim, lineHeight: 1.65, marginBottom: 20, fontStyle: "italic" }}>
        Each cell shows what's been done (or not) for each framework × substrate pair. Where most cells are partial or open is itself the central insight: the field is wide open for cross-substrate comparative work.
      </div>

      {/* Status legend */}
      <div style={{ display: "flex", gap: 12, marginBottom: 18, flexWrap: "wrap" }}>
        {["done", "partial", "open"].map(s => (
          <span key={s} style={{
            fontSize: 10.5, fontFamily: "ui-monospace, monospace",
            color: statusColor(s),
            background: `${statusColor(s)}1a`,
            border: `1px solid ${statusColor(s)}55`,
            padding: "2px 8px", borderRadius: 3, fontWeight: 700, letterSpacing: 0.5,
          }}>{statusLabel(s)}</span>
        ))}
      </div>

      {substrates.map(sub => {
        const fws = AGENT_SUBSTRATE_GRID.filter(c => c.substrate === sub.k);
        return (
          <div key={sub.k} style={{ marginBottom: 22 }}>
            <div style={{
              fontSize: 12, color: sub.color, fontFamily: "ui-monospace, monospace",
              letterSpacing: 0.7, fontWeight: 700, marginBottom: 8,
              paddingBottom: 6, borderBottom: `1px solid ${sub.color}44`,
            }}>
              {sub.label.toUpperCase()}
            </div>
            {fws.map((cell, i) => {
              const fw = FRAMEWORKS[cell.fw] || { color: C.muted, short: cell.fw.toUpperCase(), label: cell.fw };
              return (
                <div key={i} style={{
                  display: "grid", gridTemplateColumns: "100px 80px 1fr",
                  gap: 14, alignItems: "start",
                  padding: "10px 12px", borderRadius: 5,
                  background: i % 2 === 0 ? C.surface : "transparent",
                  marginBottom: 4,
                }}>
                  <div style={{
                    fontSize: 11.5, color: fw.color, fontFamily: "ui-monospace, monospace",
                    fontWeight: 700, paddingTop: 1,
                  }}>{fw.short} <span style={{ color: C.muted, fontWeight: 400 }}>· {fw.label}</span></div>
                  <div style={{
                    fontSize: 9.5, color: statusColor(cell.status),
                    background: `${statusColor(cell.status)}1a`,
                    border: `1px solid ${statusColor(cell.status)}55`,
                    padding: "2px 6px", borderRadius: 3,
                    fontFamily: "ui-monospace, monospace", fontWeight: 700,
                    letterSpacing: 0.5, textAlign: "center", height: "fit-content",
                  }}>{statusLabel(cell.status)}</div>
                  <div style={{ fontSize: 12.5, color: C.text, lineHeight: 1.55 }}>
                    {cell.note}
                  </div>
                </div>
              );
            })}
          </div>
        );
      })}

      <div style={{
        marginTop: 18, padding: "12px 16px",
        background: `${C.accent}0a`, border: `1px solid ${C.accent}33`,
        borderRadius: 6, fontSize: 12.5, color: C.text, lineHeight: 1.65,
      }}>
        <strong>Reading the grid.</strong> Most "done" cells are brain-side (FEP, causal emergence). AI is mostly open. Society sits in between, with computational mechanics on financial data and inductive game theory on macaques providing the strongest precedents. The pattern reveals where to look: cross-substrate replications of established brain methods on social and AI data are tractable, high-value, and unexploited.
      </div>
    </>
  );
}

function AgentsProposals() {
  return (
    <>
      <div style={{ fontSize: 11, color: C.accent, fontWeight: 700, letterSpacing: 1, textTransform: "uppercase", marginBottom: 8 }}>
        Agentic Systems · Research Proposals
      </div>
      <div style={{ fontSize: 22, fontWeight: 600, marginBottom: 14, letterSpacing: -0.3 }}>
        Ten cross-framework projects
      </div>
      <div style={{ fontSize: 13, color: C.textDim, lineHeight: 1.65, marginBottom: 16, fontStyle: "italic" }}>
        Each proposal includes hypothesis, falsification criterion, code/data pointers, and risk estimate. Marked "PRIORITY" if low-risk and high-information. Designed to be doable by a small team or single researcher with current tools.
      </div>

      <div style={{
        background: `${C.accent}10`, border: `1px solid ${C.accent}55`,
        borderLeft: `4px solid ${C.accent}`,
        borderRadius: 6, padding: "12px 16px", marginBottom: 20,
        fontSize: 12.5, color: C.text, lineHeight: 1.65,
      }}>
        <strong>Recommended sequence:</strong> Start with <strong>P9</strong> (cross-framework concordance test) on a public dataset — low-risk, high-information about whether the frameworks even agree on toy cases. Then <strong>P2</strong> (A* across substrates) with three matched datasets. Then <strong>P8</strong> (LLM ensembles as research instruments) once you have baseline calibration.
      </div>

      {AGENT_PROPOSALS.map((p, i) => (
        <div key={i} style={{
          marginBottom: 16,
          background: C.surface, border: `1px solid ${C.border}`,
          borderLeft: `4px solid ${p.priority ? C.accent : C.muted}`,
          borderRadius: 6, padding: "14px 18px",
        }}>
          <div style={{ display: "flex", alignItems: "baseline", gap: 10, marginBottom: 8, flexWrap: "wrap" }}>
            <div style={{
              fontSize: 10.5, color: C.accent, fontFamily: "ui-monospace, monospace",
              letterSpacing: 0.5, fontWeight: 700,
              background: `${C.accent}14`, border: `1px solid ${C.accent}55`,
              padding: "2px 7px", borderRadius: 3,
            }}>{p.id}</div>
            <div style={{ fontSize: 14, fontWeight: 600 }}>{p.title}</div>
            {p.priority && (
              <span style={{
                fontSize: 9.5, color: C.accent, background: `${C.accent}1a`,
                border: `1px solid ${C.accent}66`, padding: "1px 7px", borderRadius: 3,
                fontFamily: "ui-monospace, monospace", fontWeight: 700, letterSpacing: 0.5,
              }}>PRIORITY</span>
            )}
            <span style={{
              fontSize: 10, color: C.muted, marginLeft: "auto",
              fontFamily: "ui-monospace, monospace",
            }}>
              risk: <span style={{ color: C.text }}>{p.risk?.split("—")[0]?.trim()}</span>
            </span>
          </div>

          {/* Framework + substrate tags */}
          <div style={{ display: "flex", gap: 5, flexWrap: "wrap", marginBottom: 10 }}>
            {p.frameworks.map(fwk => {
              const fw = FRAMEWORKS[fwk] || { color: C.muted, short: fwk.toUpperCase() };
              return (
                <span key={fwk} style={{
                  fontSize: 9.5, color: fw.color, background: `${fw.color}14`,
                  border: `1px solid ${fw.color}55`, padding: "2px 6px", borderRadius: 3,
                  fontFamily: "ui-monospace, monospace", fontWeight: 700, letterSpacing: 0.4,
                }}>{fw.short}</span>
              );
            })}
            {p.substrates.map(sub => (
              <span key={sub} style={{
                fontSize: 9.5, color: C.textDim, background: C.surface2,
                border: `1px solid ${C.border}`, padding: "2px 6px", borderRadius: 3,
                fontFamily: "ui-monospace, monospace", letterSpacing: 0.4,
              }}>{sub}</span>
            ))}
          </div>

          <AgentDefField label="SUMMARY" content={p.summary} color={C.text} />
          <AgentDefField label="HYPOTHESIS" content={p.hypothesis} color="#10b981" />
          <AgentDefField label="FALSIFICATION" content={p.falsification} color="#ef4444" />
          <AgentDefField label="CODE / TOOLING" content={p.code} color={C.muted} mono />
          <AgentDefField label="RISK" content={p.risk} color={C.muted} italic />
        </div>
      ))}
    </>
  );
}

function AgentsComparative() {
  return (
    <>
      <div style={{ fontSize: 11, color: C.accent, fontWeight: 700, letterSpacing: 1, textTransform: "uppercase", marginBottom: 8 }}>
        Agentic Systems · Comparative
      </div>
      <div style={{ fontSize: 22, fontWeight: 600, marginBottom: 14, letterSpacing: -0.3 }}>
        What's shared and what differs across substrate pairs
      </div>
      <div style={{ fontSize: 13, color: C.textDim, lineHeight: 1.65, marginBottom: 22, fontStyle: "italic" }}>
        The comparative dimension is the central angle: agents-as-research-instruments works only if you can move measurements across substrates. Here's what aligns and what doesn't.
      </div>

      {AGENT_COMPARATIVE.map((c, i) => (
        <div key={i} style={{
          marginBottom: 16,
          background: C.surface, border: `1px solid ${C.border}`,
          borderRadius: 6, padding: "16px 20px",
        }}>
          <div style={{
            fontSize: 14, fontWeight: 700, marginBottom: 12,
            fontFamily: "ui-monospace, monospace", color: C.text,
            letterSpacing: 0.3,
          }}>{c.pair}</div>

          <div style={{ marginBottom: 10 }}>
            <div style={{
              fontSize: 10, color: "#10b981", fontFamily: "ui-monospace, monospace",
              letterSpacing: 0.6, fontWeight: 700, marginBottom: 4,
            }}>SHARED STRUCTURE</div>
            <div style={{ fontSize: 12.5, color: C.text, lineHeight: 1.6 }}>
              {c.shared}
            </div>
          </div>

          <div>
            <div style={{
              fontSize: 10, color: "#f59e0b", fontFamily: "ui-monospace, monospace",
              letterSpacing: 0.6, fontWeight: 700, marginBottom: 4,
            }}>DIVERGENT STRUCTURE</div>
            <div style={{ fontSize: 12.5, color: C.text, lineHeight: 1.6 }}>
              {c.divergent}
            </div>
          </div>
        </div>
      ))}

      <div style={{
        marginTop: 16, padding: "12px 16px",
        background: `${C.accent}0a`, border: `1px solid ${C.accent}33`,
        borderRadius: 6, fontSize: 12.5, color: C.text, lineHeight: 1.65,
      }}>
        <strong>The empirical opening.</strong> No published study runs the same formal measure (A*, ΦID-emergence, EI) across all three substrates with comparable data resolution. The convergent structure across pairs suggests such measures should yield comparable results; the divergent structure predicts where they won't. Either outcome is publishable; both are informative.
      </div>
    </>
  );
}

function AgentsCritiques() {
  return (
    <>
      <div style={{ fontSize: 11, color: C.accent, fontWeight: 700, letterSpacing: 1, textTransform: "uppercase", marginBottom: 8 }}>
        Agentic Systems · Critiques
      </div>
      <div style={{ fontSize: 22, fontWeight: 600, marginBottom: 14, letterSpacing: -0.3 }}>
        Where the frameworks fail or are contested
      </div>
      <div style={{ fontSize: 13, color: C.textDim, lineHeight: 1.65, marginBottom: 22, fontStyle: "italic" }}>
        Honest accounting. Each formal definition of agency has serious critics. Read these before designing any project — a proposal that ignores its target framework's critiques will be harder to defend.
      </div>

      {AGENT_CRITIQUES.map((c, i) => (
        <div key={i} style={{
          marginBottom: 14,
          background: C.surface, border: `1px solid ${C.border}`,
          borderLeft: "4px solid #ef4444",
          borderRadius: 6, padding: "14px 18px",
        }}>
          <div style={{ fontSize: 13.5, fontWeight: 700, marginBottom: 6, color: C.text }}>
            {c.target}
          </div>
          <div style={{
            fontSize: 11, color: "#f59e0b",
            fontFamily: "ui-monospace, monospace", letterSpacing: 0.3,
            marginBottom: 8, fontStyle: "italic",
          }}>
            {c.critics}
          </div>
          <div style={{ fontSize: 12.5, color: C.text, lineHeight: 1.65 }}>
            {c.point}
          </div>
        </div>
      ))}

      <div style={{
        marginTop: 20, padding: "12px 16px",
        background: "#fef2f240", border: "1px solid #ef444455",
        borderRadius: 6, fontSize: 12.5, color: C.text, lineHeight: 1.65,
      }}>
        <strong>How to handle these in research.</strong> Don't pick one framework and defend it — pick a question and use multiple frameworks to triangulate. If your proposal depends on a contested step (e.g., Markov blanket detection in non-equilibrium systems), test that step explicitly against the critique. Negative results that demonstrate the critique are themselves publishable and more honest than positive results that ignore it.
      </div>
    </>
  );
}

// ─── FRAMEWORKS TAB ──────────────────────────────────────────────────────────
function FrameworksTab() {
  const list = Object.entries(FRAMEWORKS);
  const anchors = list.filter(([, f]) => f.category === "anchor" || f.isAnchor);
  const productive = list.filter(([, f]) => f.category === "productive");
  const metaphysical = list.filter(([, f]) => f.category === "metaphysical");
  const [openId, setOpenId] = useState(null);

  return (
    <div style={{ padding: "24px 32px 60px", maxWidth: 1000, margin: "0 auto" }}>
      <div style={{ marginBottom: 22 }}>
        <div style={{ fontSize: 16, fontWeight: 600, marginBottom: 6 }}>The frameworks</div>
        <div style={{ fontSize: 12.5, color: C.textDim, lineHeight: 1.65 }}>
          Three categories. <span style={{ color: C.sr, fontWeight: 600 }}>Anchors</span> set the ontological and quantitative ground.
          <span style={{ color: C.pc, fontWeight: 600 }}> Productive frameworks </span>
          contribute working machinery — specific math with track records.
          <span style={{ color: C.pro, fontWeight: 600 }}> Metaphysical systems </span>
          provide the ontological foundations the productive frameworks usually take for granted. Click any card for origin, principles, formulas, controversies, and opposing views.
        </div>
      </div>

      <div style={{ marginBottom: 22 }}>
        <div style={{ fontSize: 11, color: C.muted, fontFamily: "ui-monospace, monospace", letterSpacing: 0.5, marginBottom: 10, fontWeight: 600 }}>ANCHORS</div>
        {anchors.map(([k, f]) => (
          <FrameworkCard key={k} k={k} f={f} isAnchor open={openId === k} onToggle={() => setOpenId(openId === k ? null : k)} />
        ))}
      </div>

      <div style={{ marginBottom: 22 }}>
        <div style={{ fontSize: 11, color: C.muted, fontFamily: "ui-monospace, monospace", letterSpacing: 0.5, marginBottom: 10, fontWeight: 600 }}>PRODUCTIVE FRAMEWORKS</div>
        {productive.map(([k, f]) => (
          <FrameworkCard key={k} k={k} f={f} isAnchor={false} open={openId === k} onToggle={() => setOpenId(openId === k ? null : k)} />
        ))}
      </div>

      <div>
        <div style={{ fontSize: 11, color: C.muted, fontFamily: "ui-monospace, monospace", letterSpacing: 0.5, marginBottom: 10, fontWeight: 600 }}>METAPHYSICAL SYSTEMS</div>
        <div style={{ fontSize: 11.5, color: C.textDim, lineHeight: 1.6, marginBottom: 10, fontStyle: "italic" }}>
          Qualitative ontological programs that engage actively with current philosophy of science. Each provides a different answer to "what kind of thing is this concept about?" — and each can derive, constrain, or oppose the productive frameworks.
        </div>
        {metaphysical.map(([k, f]) => (
          <FrameworkCard key={k} k={k} f={f} isAnchor={false} open={openId === k} onToggle={() => setOpenId(openId === k ? null : k)} />
        ))}
      </div>
    </div>
  );
}

function FrameworkCard({ k, f, isAnchor, open, onToggle }) {
  return (
    <div style={{
      marginBottom: isAnchor ? 12 : 10,
      background: isAnchor ? `${f.color}08` : C.surface,
      border: `1px solid ${isAnchor ? `${f.color}33` : C.border}`,
      borderLeft: `${isAnchor ? 4 : 3}px solid ${f.color}`,
      borderRadius: 6,
      overflow: "hidden",
    }}>
      <div onClick={onToggle} style={{
        padding: isAnchor ? "14px 16px" : "12px 14px",
        cursor: "pointer",
        transition: "background 120ms",
      }}>
        <div style={{ display: "flex", alignItems: "baseline", gap: 10, marginBottom: 6 }}>
          <div style={{
            fontSize: 10, color: C.muted, fontFamily: "ui-monospace, monospace",
            width: 14, textAlign: "center", userSelect: "none",
          }}>{open ? "▾" : "▸"}</div>
          <div style={{
            fontSize: isAnchor ? 10.5 : 10, color: f.color, fontFamily: "ui-monospace, monospace",
            letterSpacing: 0.5, fontWeight: 700,
            background: `${f.color}14`, border: `1px solid ${f.color}33`,
            padding: isAnchor ? "2px 7px" : "1px 6px", borderRadius: 3,
          }}>{f.short}</div>
          <div style={{ fontSize: isAnchor ? 15 : 14, fontWeight: 600 }}>{f.label}</div>
        </div>
        <div style={{ fontSize: isAnchor ? 12.5 : 12, color: isAnchor ? C.text : C.textDim, lineHeight: 1.6, paddingLeft: 24 }}>
          {f.desc}
        </div>
        {f.purpose && (
          <div style={{
            marginTop: 10, marginLeft: 24, padding: "8px 12px",
            background: `${f.color}0e`,
            borderLeft: `2px solid ${f.color}66`,
            borderRadius: 3,
          }}>
            <div style={{
              fontSize: 10, color: f.color, fontFamily: "ui-monospace, monospace",
              letterSpacing: 0.6, fontWeight: 700, marginBottom: 4,
            }}>
              WHAT THIS FRAMEWORK ADDS
            </div>
            <div style={{ fontSize: 12, color: C.text, lineHeight: 1.6 }}>
              {f.purpose}
            </div>
          </div>
        )}
      </div>

      {open && (
        <div style={{
          padding: "0 18px 18px 38px",
          borderTop: `1px solid ${C.border}`,
        }}>
          {f.origin && (
            <FrameworkSection title="ORIGIN" color={f.color}>
              <div style={{ fontSize: 12.5, color: C.text, lineHeight: 1.6 }}>{f.origin}</div>
            </FrameworkSection>
          )}

          {f.thinkers && f.thinkers.length > 0 && (
            <FrameworkSection title="KEY THINKERS" color={f.color}>
              <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
                {f.thinkers.map((t, i) => (
                  <span key={i} style={{
                    fontSize: 11.5, color: C.textDim, background: C.surface2,
                    border: `1px solid ${C.border}`, padding: "2px 8px", borderRadius: 12,
                  }}>{t}</span>
                ))}
              </div>
            </FrameworkSection>
          )}

          {f.principles && f.principles.length > 0 && (
            <FrameworkSection title="CORE PRINCIPLES" color={f.color}>
              {f.principles.map((p, i) => (
                <div key={i} style={{
                  fontSize: 12.5, color: C.text, lineHeight: 1.6,
                  paddingLeft: 14, position: "relative",
                  marginBottom: i < f.principles.length - 1 ? 8 : 0,
                }}>
                  <span style={{ position: "absolute", left: 0, color: f.color }}>•</span>{p}
                </div>
              ))}
            </FrameworkSection>
          )}

          {f.formulas && f.formulas.length > 0 && (
            <FrameworkSection title="KEY FORMULAS" color={f.color}>
              <div style={{
                background: C.surface2, border: `1px solid ${C.border}`,
                borderRadius: 4, padding: "10px 12px",
              }}>
                {f.formulas.map((entry, i) => (
                  <div key={i} style={{
                    display: "grid", gridTemplateColumns: "minmax(0, 1.2fr) minmax(0, 1fr)",
                    gap: 14, alignItems: "baseline",
                    paddingBottom: i < f.formulas.length - 1 ? 7 : 0,
                    marginBottom: i < f.formulas.length - 1 ? 7 : 0,
                    borderBottom: i < f.formulas.length - 1 ? `1px solid ${C.border}` : "none",
                  }}>
                    <code style={{
                      fontSize: 12, color: C.text,
                      fontFamily: "ui-monospace, 'IBM Plex Mono', monospace",
                      whiteSpace: "pre-wrap", wordBreak: "break-word",
                      lineHeight: 1.7,
                    }}>{renderFormula(entry.f)}</code>
                    <span style={{ fontSize: 11, color: C.muted, fontStyle: "italic" }}>
                      {entry.label}
                    </span>
                  </div>
                ))}
              </div>
            </FrameworkSection>
          )}

          {f.controversies && f.controversies.length > 0 && (
            <FrameworkSection title="LIVE CONTROVERSIES" color={C.open}>
              {f.controversies.map((c, i) => (
                <div key={i} style={{
                  fontSize: 12.5, color: C.text, lineHeight: 1.55,
                  paddingLeft: 14, position: "relative", fontStyle: "italic",
                  marginBottom: i < f.controversies.length - 1 ? 7 : 0,
                }}>
                  <span style={{ position: "absolute", left: 0, color: C.open }}>⚠</span>{c}
                </div>
              ))}
            </FrameworkSection>
          )}

          {f.opposing && f.opposing.length > 0 && (
            <FrameworkSection title="OPPOSING VIEWS / RIVAL FRAMEWORKS" color="#ef4444">
              {f.opposing.map((o, i) => (
                <div key={i} style={{
                  padding: "8px 10px",
                  background: "#ef44440a",
                  border: "1px solid #ef444433",
                  borderRadius: 4,
                  marginBottom: i < f.opposing.length - 1 ? 6 : 0,
                }}>
                  <div style={{ display: "flex", alignItems: "baseline", gap: 8, flexWrap: "wrap", marginBottom: 4 }}>
                    <span style={{ fontSize: 12.5, fontWeight: 600, color: C.text }}>{o.name}</span>
                    {o.who && (
                      <span style={{ fontSize: 10.5, color: C.muted, fontFamily: "ui-monospace, monospace" }}>
                        — {o.who}
                      </span>
                    )}
                  </div>
                  <div style={{ fontSize: 11.5, color: C.textDim, lineHeight: 1.5 }}>{o.brief}</div>
                </div>
              ))}
            </FrameworkSection>
          )}
        </div>
      )}
    </div>
  );
}

function FrameworkSection({ title, color, children }) {
  return (
    <div style={{ marginTop: 14 }}>
      <div style={{
        fontSize: 10, color: color, fontFamily: "ui-monospace, monospace",
        letterSpacing: 0.7, fontWeight: 700, marginBottom: 8,
      }}>{title}</div>
      {children}
    </div>
  );
}

// ─── GRAPH TAB ───────────────────────────────────────────────────────────────
// Helper: 6-point hexagon path centered at (cx, cy) with circumradius r.
function hexPoints(cx, cy, r) {
  const pts = [];
  for (let i = 0; i < 6; i++) {
    const a = (Math.PI / 3) * i - Math.PI / 2; // start at top
    pts.push(`${cx + r * Math.cos(a)},${cy + r * Math.sin(a)}`);
  }
  return pts.join(" ");
}

function GraphTab({ setTab }) {
  const [pinnedId, setPinnedId] = useState(null);
  const [hoveredId, setHoveredId] = useState(null);
  const [activeTypes, setActiveTypes] = useState({
    opposes: true, tension: true, uses: true, extends: true, grounds: true, compatible: true,
  });
  const [showClusters, setShowClusters] = useState(true);
  const [showAxis, setShowAxis] = useState(true);

  // Effective focus: pinned takes priority, hover is preview
  const focusId = pinnedId || hoveredId;

  const SVG_W = 1180, SVG_H = 820;
  const NODE_R = 28;          // base radius
  const FOCUSED_R = 34;       // focused radius

  // Build framework usage count (how many concepts reference each framework)
  // This is computed once and used for visual weight on the node.
  const fwUsage = useMemo(() => {
    const counts = {};
    for (const c of CONCEPTS) {
      if (!c.views) continue;
      for (const k of Object.keys(c.views)) {
        counts[k] = (counts[k] || 0) + 1;
      }
    }
    return counts;
  }, []);

  // Node radius scales modestly with usage (cap range visually)
  const radiusFor = (key) => {
    const usage = fwUsage[key] || 0;
    // Anchors get a slight bump
    const isAnchor = FRAMEWORKS[key]?.category === "anchor";
    const base = NODE_R + Math.min(8, usage * 0.18) + (isAnchor ? 4 : 0);
    return focusId === key ? base + 6 : base;
  };

  const visibleRelations = FRAMEWORK_RELATIONS.filter(r => activeTypes[r.type]);

  const isEdgeFocused = (r) =>
    focusId && (r.from === focusId || r.to === focusId);
  const isNodeFocused = (k) => {
    if (!focusId) return true;
    if (focusId === k) return true;
    return visibleRelations.some(r =>
      (r.from === focusId && r.to === k) ||
      (r.to === focusId && r.from === k)
    );
  };

  const focusedRelations = focusId
    ? visibleRelations
        .filter(r => r.from === focusId || r.to === focusId)
        .map(r => {
          const otherKey = r.from === focusId ? r.to : r.from;
          const direction = r.from === focusId ? "outgoing" : "incoming";
          return { ...r, otherKey, direction };
        })
    : [];

  // Compute cluster hulls (convex hull of member node positions, padded, smoothed)
  const clusterPaths = FW_CLUSTERS.map((cl, idx) => {
    const pts = cl.members.map(m => fwPos(m)).filter(Boolean);
    if (pts.length < 2) return null;
    const cx = pts.reduce((s, p) => s + p.x, 0) / pts.length;
    const cy = pts.reduce((s, p) => s + p.y, 0) / pts.length;
    const sorted = pts.slice().sort((a, b) => Math.atan2(a.y - cy, a.x - cx) - Math.atan2(b.y - cy, b.x - cx));
    // Vary padding: small clusters get more padding to be visible; large clusters less to reduce overlap
    const PAD = pts.length <= 3 ? 58 : pts.length <= 5 ? 50 : 42;
    const padded = sorted.map(p => {
      const dx = p.x - cx, dy = p.y - cy;
      const len = Math.sqrt(dx*dx + dy*dy) || 1;
      return { x: p.x + (dx/len) * PAD, y: p.y + (dy/len) * PAD };
    });
    // Smooth curve via quadratic Bezier through midpoints
    let d = "";
    for (let i = 0; i < padded.length; i++) {
      const p = padded[i];
      const next = padded[(i + 1) % padded.length];
      const mid = { x: (p.x + next.x) / 2, y: (p.y + next.y) / 2 };
      if (i === 0) d += `M ${mid.x.toFixed(1)},${mid.y.toFixed(1)} `;
      d += `Q ${next.x.toFixed(1)},${next.y.toFixed(1)} `;
      const nextNext = padded[(i + 2) % padded.length];
      const nextMid = { x: (next.x + nextNext.x) / 2, y: (next.y + nextNext.y) / 2 };
      d += `${nextMid.x.toFixed(1)},${nextMid.y.toFixed(1)} `;
    }
    d += "Z";
    return { ...cl, d };
  }).filter(Boolean);

  const handleNodeClick = (k) => {
    setPinnedId(pinnedId === k ? null : k);
  };

  const focusedFw = focusId ? FRAMEWORKS[focusId] : null;

  return (
    <div style={{ padding: "20px 24px 60px" }}>
      {/* HEADER */}
      <div style={{ marginBottom: 16, maxWidth: 1100 }}>
        <div style={{ fontSize: 16, fontWeight: 600, marginBottom: 6 }}>Framework Graph</div>
        <div style={{ fontSize: 12.5, color: C.textDim, lineHeight: 1.6, marginBottom: 14 }}>
          17 frameworks positioned by two analytical dimensions:
          <span style={{ color: C.text, fontWeight: 600 }}> horizontal = mathematical maturity </span>
          (qualitative ← → fully formalized) and
          <span style={{ color: C.text, fontWeight: 600 }}> vertical = substrate independence </span>
          (substrate-tied ↓ ↑ universal).
          Shape encodes category: hexagon = anchor, circle = productive, square = metaphysical.
          {" "}
          <span style={{ color: C.muted }}>Hover for preview · click to pin (then scroll to read details below).</span>
        </div>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
          <span style={{ fontSize: 10.5, color: C.muted, fontFamily: "ui-monospace, monospace", letterSpacing: 0.3, marginRight: 6 }}>EDGES</span>
          {Object.entries(EDGE_TYPES).map(([type, ec]) => (
            <button
              key={type}
              onClick={() => setActiveTypes(a => ({ ...a, [type]: !a[type] }))}
              style={{
                display: "inline-flex", alignItems: "center", gap: 8,
                background: activeTypes[type] ? `${ec.color}1f` : "transparent",
                color: activeTypes[type] ? ec.color : C.mutedDeep,
                border: `1px solid ${activeTypes[type] ? `${ec.color}55` : C.border}`,
                borderRadius: 5, padding: "4px 10px", fontSize: 10.5,
                fontFamily: "ui-monospace, monospace", letterSpacing: 0.3,
                cursor: "pointer", transition: "all 120ms",
                fontWeight: activeTypes[type] ? 600 : 400,
              }}
              title={ec.desc}
            >
              <EdgeGlyph ec={ec} />
              {ec.label}
            </button>
          ))}
          <span style={{ marginLeft: 8, display: "flex", gap: 6 }}>
            <button onClick={() => setShowClusters(s => !s)}
              style={{
                background: showClusters ? `${C.muted}1f` : "transparent",
                color: showClusters ? C.text : C.mutedDeep,
                border: `1px solid ${C.border}`, borderRadius: 5, padding: "4px 10px",
                fontSize: 10.5, fontFamily: "ui-monospace, monospace", cursor: "pointer",
                letterSpacing: 0.3,
              }}>clusters</button>
            <button onClick={() => setShowAxis(s => !s)}
              style={{
                background: showAxis ? `${C.muted}1f` : "transparent",
                color: showAxis ? C.text : C.mutedDeep,
                border: `1px solid ${C.border}`, borderRadius: 5, padding: "4px 10px",
                fontSize: 10.5, fontFamily: "ui-monospace, monospace", cursor: "pointer",
                letterSpacing: 0.3,
              }}>axis</button>
          </span>
          <span style={{ marginLeft: "auto", fontSize: 11, color: C.muted, fontFamily: "ui-monospace, monospace" }}>
            {visibleRelations.length} / {FRAMEWORK_RELATIONS.length} edges
          </span>
        </div>
      </div>

      {/* SVG GRAPH */}
      <div style={{
        background: C.surface, border: `1px solid ${C.border}`,
        borderRadius: 8, padding: 8, marginBottom: 16, position: "relative",
      }}>
        <svg viewBox={`0 0 ${SVG_W} ${SVG_H}`} style={{ width: "100%", height: "auto", display: "block" }}
          onClick={(e) => { if (e.target.tagName === "svg") setPinnedId(null); }}>
          <defs>
            {/* Arrowheads (filled triangle) */}
            {Object.entries(EDGE_TYPES).map(([type, ec]) => ec.terminator === "arrow" && (
              <marker key={`arrow-${type}`} id={`arrow-${type}`} viewBox="0 0 10 10" refX="9" refY="5"
                markerWidth="6" markerHeight="6" orient="auto-start-reverse">
                <path d="M 0 0 L 10 5 L 0 10 z" fill={ec.color} />
              </marker>
            ))}
            {/* Double arrowheads (for `extends`) */}
            {Object.entries(EDGE_TYPES).map(([type, ec]) => ec.terminator === "double" && (
              <marker key={`double-${type}`} id={`double-${type}`} viewBox="0 0 14 10" refX="13" refY="5"
                markerWidth="9" markerHeight="6" orient="auto-start-reverse">
                <path d="M 0 0 L 7 5 L 0 10 z M 7 0 L 14 5 L 7 10 z" fill={ec.color} />
              </marker>
            ))}
            {/* Circle terminators (for `grounds` — "rests on") */}
            {Object.entries(EDGE_TYPES).map(([type, ec]) => ec.terminator === "circle" && (
              <marker key={`circle-${type}`} id={`circle-${type}`} viewBox="0 0 10 10" refX="9" refY="5"
                markerWidth="7" markerHeight="7" orient="auto-start-reverse">
                <circle cx="6" cy="5" r="3.2" fill={ec.color} />
              </marker>
            ))}
            {/* Subtle drop shadow for nodes */}
            <filter id="nodeShadow" x="-50%" y="-50%" width="200%" height="200%">
              <feGaussianBlur in="SourceAlpha" stdDeviation="2.5" />
              <feOffset dy="1" />
              <feComponentTransfer><feFuncA type="linear" slope="0.35" /></feComponentTransfer>
              <feMerge><feMergeNode /><feMergeNode in="SourceGraphic" /></feMerge>
            </filter>
          </defs>

          {/* AXES — both meaningful */}
          {showAxis && (
            <g opacity="0.65">
              {/* X-axis: mathematical maturity */}
              <line x1={FW_AXIS.xMin} y1={SVG_H - 30} x2={FW_AXIS.xMax} y2={SVG_H - 30}
                stroke={C.border} strokeWidth="1" />
              <text x={FW_AXIS.xMin} y={SVG_H - 12} fontSize="10" fill={C.mutedDeep}
                fontFamily="ui-monospace, monospace" letterSpacing="0.5">
                ← qualitative / interpretive
              </text>
              <text x={(FW_AXIS.xMin + FW_AXIS.xMax) / 2} y={SVG_H - 12} fontSize="10"
                fill={C.muted} fontFamily="ui-monospace, monospace" letterSpacing="0.5"
                textAnchor="middle" fontWeight="600">
                MATHEMATICAL MATURITY
              </text>
              <text x={FW_AXIS.xMax} y={SVG_H - 12} fontSize="10" fill={C.mutedDeep}
                fontFamily="ui-monospace, monospace" letterSpacing="0.5" textAnchor="end">
                formal mathematics →
              </text>
              {/* X-axis tick marks */}
              {[25, 50, 75].map(t => {
                const x = FW_AXIS.xMin + (t/100) * (FW_AXIS.xMax - FW_AXIS.xMin);
                return (
                  <line key={`xt-${t}`} x1={x} y1={SVG_H - 33} x2={x} y2={SVG_H - 27}
                    stroke={C.mutedDeep} strokeWidth="0.8" />
                );
              })}

              {/* Y-axis: substrate independence */}
              <line x1={70} y1={FW_AXIS.yMin} x2={70} y2={FW_AXIS.yMax}
                stroke={C.border} strokeWidth="1" />
              {/* Y-axis labels (rotated text) */}
              <text x={28} y={FW_AXIS.yMin + 8} fontSize="10" fill={C.mutedDeep}
                fontFamily="ui-monospace, monospace" letterSpacing="0.5">
                ↑ universal
              </text>
              <text
                transform={`translate(28 ${(FW_AXIS.yMin + FW_AXIS.yMax) / 2}) rotate(-90)`}
                fontSize="10" fill={C.muted} fontFamily="ui-monospace, monospace"
                letterSpacing="0.5" textAnchor="middle" fontWeight="600">
                SUBSTRATE INDEPENDENCE
              </text>
              <text x={28} y={FW_AXIS.yMax} fontSize="10" fill={C.mutedDeep}
                fontFamily="ui-monospace, monospace" letterSpacing="0.5">
                ↓ substrate-tied
              </text>
              {/* Y-axis tick marks */}
              {[25, 50, 75].map(t => {
                const y = FW_AXIS.yMax - (t/100) * (FW_AXIS.yMax - FW_AXIS.yMin);
                return (
                  <line key={`yt-${t}`} x1={67} y1={y} x2={73} y2={y}
                    stroke={C.mutedDeep} strokeWidth="0.8" />
                );
              })}
            </g>
          )}

          {/* Cluster hulls — brighter and more readable */}
          {showClusters && clusterPaths.map((cl, idx) => (
            <g key={cl.name} opacity={focusId ? 0.22 : 1}>
              <path d={cl.d} fill={cl.color} fillOpacity="0.18" stroke={cl.color}
                strokeOpacity="0.75" strokeWidth="1.8" strokeLinejoin="round" />
            </g>
          ))}
          {/* Cluster name labels with background pills for readability */}
          {showClusters && !focusId && clusterPaths.map((cl, idx) => {
            const pts = cl.members.map(m => fwPos(m)).filter(Boolean);
            const cx = pts.reduce((s, p) => s + p.x, 0) / pts.length;
            const minY = Math.min(...pts.map(p => p.y));
            // Stagger label vertical offset to reduce overlap between adjacent clusters
            const stagger = (idx % 3) * 14;
            const cy = minY - 38 - stagger;
            // Approximate label width — 6.5px per char for monospace at this size
            const labelW = cl.name.length * 6.8 + 18;
            return (
              <g key={cl.name}>
                <rect
                  x={cx - labelW / 2}
                  y={cy - 11}
                  width={labelW}
                  height={17}
                  rx={3}
                  fill={C.bg}
                  stroke={cl.color}
                  strokeOpacity="0.6"
                  strokeWidth="1"
                />
                <text x={cx} y={cy + 1} fontSize="10.5" fill={cl.color}
                  fontFamily="ui-monospace, monospace" letterSpacing="0.5"
                  textAnchor="middle" fontWeight="700">
                  {cl.name}
                </text>
              </g>
            );
          })}

          {/* Edges */}
          {visibleRelations.map((r, i) => {
            const from = fwPos(r.from);
            const to = fwPos(r.to);
            if (!from || !to) return null;
            const ec = EDGE_TYPES[r.type];
            const focused = isEdgeFocused(r);
            const dimmed = focusId && !focused;

            const fromR = radiusFor(r.from);
            const toR = radiusFor(r.to);

            const dx = to.x - from.x, dy = to.y - from.y;
            const len = Math.sqrt(dx*dx + dy*dy) || 1;
            const nx = dx / len, ny = dy / len;
            const fromX = from.x + nx * fromR;
            const fromY = from.y + ny * fromR;
            const toX = to.x - nx * toR;
            const toY = to.y - ny * toR;

            // Choose appropriate marker based on terminator
            let markerEnd = undefined;
            if (focused || !focusId) {
              if (ec.terminator === "arrow") markerEnd = `url(#arrow-${r.type})`;
              else if (ec.terminator === "double") markerEnd = `url(#double-${r.type})`;
              else if (ec.terminator === "circle") markerEnd = `url(#circle-${r.type})`;
            }

            const baseOpacity = dimmed ? 0.06 : (focused ? 1 : ec.opacity);
            const strokeWidth = focused ? Math.max(ec.width, 2.4) : ec.width;

            // Edge midpoint for label
            const midX = (fromX + toX) / 2;
            const midY = (fromY + toY) / 2;

            return (
              <g key={i}>
                <line
                  x1={fromX} y1={fromY} x2={toX} y2={toY}
                  stroke={ec.color}
                  strokeWidth={strokeWidth}
                  strokeOpacity={baseOpacity}
                  strokeDasharray={ec.dasharray}
                  strokeLinecap="round"
                  markerEnd={markerEnd}
                />
                {focused && (
                  <g>
                    <rect x={midX - 28} y={midY - 9} width="56" height="16" rx="3"
                      fill={C.surface} stroke={ec.color} strokeOpacity="0.55" strokeWidth="0.8" />
                    <text x={midX} y={midY + 3} fontSize="9.5" fill={ec.color}
                      fontFamily="ui-monospace, monospace" letterSpacing="0.4"
                      textAnchor="middle" fontWeight="600">{ec.label}</text>
                  </g>
                )}
              </g>
            );
          })}

          {/* Nodes — shape by category, position by maturity × substrate independence */}
          {Object.keys(FW_LAYOUT).map(k => {
            const pos = fwPos(k);
            const fw = FRAMEWORKS[k];
            if (!fw || !pos) return null;
            const isFocused = focusId === k;
            const isPinned = pinnedId === k;
            const inFocus = isNodeFocused(k);
            const dimmed = focusId && !inFocus;
            const r = radiusFor(k);

            // Shape per category
            const shape = fw.category === "anchor" ? "hexagon"
                        : fw.category === "metaphysical" ? "roundsquare"
                        : "circle";

            const fillColor = isFocused ? `${fw.color}55` : `${fw.color}22`;
            const strokeWidth = isFocused ? 2.8 : 1.5;

            // Pin/focus highlight ring matches shape
            const renderHighlight = () => {
              if (!isPinned) return null;
              const padR = r + 6;
              if (shape === "circle") {
                return <circle cx={pos.x} cy={pos.y} r={padR} fill="none"
                  stroke={fw.color} strokeWidth="1.5" strokeDasharray="3 3" opacity="0.7" />;
              }
              if (shape === "hexagon") {
                return <polygon points={hexPoints(pos.x, pos.y, padR)} fill="none"
                  stroke={fw.color} strokeWidth="1.5" strokeDasharray="3 3" opacity="0.7" />;
              }
              // roundsquare
              return <rect x={pos.x - padR} y={pos.y - padR} width={padR * 2} height={padR * 2}
                rx={padR * 0.32} fill="none"
                stroke={fw.color} strokeWidth="1.5" strokeDasharray="3 3" opacity="0.7" />;
            };

            const renderShape = () => {
              const commonProps = {
                fill: fillColor,
                stroke: fw.color,
                strokeWidth,
                opacity: dimmed ? 0.22 : 1,
                filter: "url(#nodeShadow)",
              };
              if (shape === "circle") {
                return <circle cx={pos.x} cy={pos.y} r={r} {...commonProps} />;
              }
              if (shape === "hexagon") {
                return <polygon points={hexPoints(pos.x, pos.y, r * 1.08)} {...commonProps} />;
              }
              // roundsquare for metaphysical
              const side = r * 1.7;
              return <rect x={pos.x - side/2} y={pos.y - side/2}
                width={side} height={side} rx={side * 0.22} {...commonProps} />;
            };

            return (
              <g key={k}
                 onMouseEnter={() => !pinnedId && setHoveredId(k)}
                 onMouseLeave={() => !pinnedId && setHoveredId(null)}
                 onClick={(e) => { e.stopPropagation(); handleNodeClick(k); }}
                 style={{ cursor: "pointer" }}>
                {renderHighlight()}
                {renderShape()}
                <text
                  x={pos.x} y={pos.y + 4}
                  textAnchor="middle"
                  fill={fw.color}
                  fontSize={isFocused ? 14 : 13}
                  fontWeight="700"
                  fontFamily="ui-monospace, 'IBM Plex Mono', monospace"
                  letterSpacing="0.5"
                  opacity={dimmed ? 0.4 : 1}
                  style={{ pointerEvents: "none" }}>
                  {fw.short}
                </text>
                {/* Full name shown ONLY when this node is the focus */}
                {isFocused && (
                  <g style={{ pointerEvents: "none" }}>
                    <rect
                      x={pos.x - (fw.label.length * 3.5 + 10)}
                      y={pos.y + r + 6}
                      width={fw.label.length * 7 + 20}
                      height={20}
                      rx={3}
                      fill={C.bg}
                      stroke={fw.color}
                      strokeOpacity="0.6"
                      strokeWidth="1"
                    />
                    <text
                      x={pos.x} y={pos.y + r + 19}
                      textAnchor="middle"
                      fill={fw.color}
                      fontSize="11.5"
                      fontWeight="600"
                      fontFamily="ui-monospace, monospace">
                      {fw.label}
                    </text>
                  </g>
                )}
              </g>
            );
          })}
        </svg>

        {/* Pin indicator */}
        {pinnedId && (
          <div style={{
            position: "absolute", top: 12, right: 12,
            display: "flex", alignItems: "center", gap: 8,
            background: C.bg, border: `1px solid ${FRAMEWORKS[pinnedId].color}66`,
            borderRadius: 5, padding: "4px 10px", fontSize: 11,
            fontFamily: "ui-monospace, monospace",
          }}>
            <span style={{ color: C.muted }}>pinned</span>
            <span style={{ color: FRAMEWORKS[pinnedId].color, fontWeight: 600 }}>{FRAMEWORKS[pinnedId].short}</span>
            <button onClick={() => setPinnedId(null)}
              style={{ background: "transparent", color: C.muted, border: "none",
                cursor: "pointer", fontSize: 14, padding: 0, lineHeight: 1 }}>×</button>
          </div>
        )}
      </div>

      {/* DETAIL PANEL */}
      {focusedFw ? (
        <FocusedFrameworkPanel
          fw={focusedFw}
          fwKey={focusId}
          isPinned={!!pinnedId}
          relations={focusedRelations}
          setTab={setTab}
          onUnpin={() => setPinnedId(null)}
        />
      ) : (
        <GraphLegendPanel />
      )}
    </div>
  );
}

// Small SVG glyph used inside the edge-type toggle buttons.
// Reproduces the actual edge style so the legend is honest.
function EdgeGlyph({ ec }) {
  const w = 32, h = 8;
  return (
    <svg width={w} height={h} viewBox={`0 0 ${w} ${h}`} style={{ display: "block" }}>
      {ec.terminator === "arrow" && (
        <marker id={`g-arrow-${ec.label}`} viewBox="0 0 10 10" refX="9" refY="5"
          markerWidth="5" markerHeight="5" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z" fill={ec.color} />
        </marker>
      )}
      {ec.terminator === "double" && (
        <marker id={`g-double-${ec.label}`} viewBox="0 0 14 10" refX="13" refY="5"
          markerWidth="7" markerHeight="5" orient="auto-start-reverse">
          <path d="M 0 0 L 7 5 L 0 10 z M 7 0 L 14 5 L 7 10 z" fill={ec.color} />
        </marker>
      )}
      {ec.terminator === "circle" && (
        <marker id={`g-circle-${ec.label}`} viewBox="0 0 10 10" refX="9" refY="5"
          markerWidth="6" markerHeight="6" orient="auto-start-reverse">
          <circle cx="6" cy="5" r="3" fill={ec.color} />
        </marker>
      )}
      <line x1="1" y1={h/2} x2={w-1} y2={h/2}
        stroke={ec.color} strokeWidth={ec.width}
        strokeDasharray={ec.dasharray} strokeLinecap="round"
        markerEnd={
          ec.terminator === "arrow" ? `url(#g-arrow-${ec.label})` :
          ec.terminator === "double" ? `url(#g-double-${ec.label})` :
          ec.terminator === "circle" ? `url(#g-circle-${ec.label})` :
          undefined
        }
      />
    </svg>
  );
}

function FocusedFrameworkPanel({ fw, fwKey, isPinned, relations, setTab, onUnpin }) {
  if (!fw) return null;
  const byType = {};
  for (const r of relations) {
    (byType[r.type] = byType[r.type] || []).push(r);
  }

  // Find cluster membership(s)
  const memberClusters = FW_CLUSTERS.filter(cl => cl.members.includes(fwKey));

  return (
    <div style={{
      background: C.surface, border: `1px solid ${C.border}`,
      borderLeft: `4px solid ${fw.color}`, borderRadius: 8, padding: "16px 20px",
    }}>
      <div style={{ display: "flex", alignItems: "baseline", gap: 12, marginBottom: 8, flexWrap: "wrap" }}>
        <div style={{
          fontSize: 10.5, color: fw.color, fontFamily: "ui-monospace, monospace",
          letterSpacing: 0.5, fontWeight: 700,
          background: `${fw.color}14`, border: `1px solid ${fw.color}33`,
          padding: "2px 7px", borderRadius: 3,
        }}>{fw.short}</div>
        <div style={{ fontSize: 15.5, fontWeight: 600 }}>{fw.label}</div>
        <span style={{
          fontSize: 10, color: C.muted, fontFamily: "ui-monospace, monospace",
          background: C.surface2, border: `1px solid ${C.border}`,
          padding: "1px 6px", borderRadius: 3, textTransform: "uppercase",
        }}>{fw.category}</span>
        <span style={{ fontSize: 11, color: C.muted, fontFamily: "ui-monospace, monospace" }}>
          {relations.length} relation{relations.length === 1 ? "" : "s"}
        </span>
        {isPinned && (
          <button onClick={onUnpin}
            style={{
              background: "transparent", color: C.muted,
              border: `1px solid ${C.border}`, borderRadius: 4,
              padding: "2px 8px", fontSize: 10.5,
              fontFamily: "ui-monospace, monospace", cursor: "pointer",
            }}>unpin</button>
        )}
        <button onClick={() => setTab("frameworks")}
          style={{
            marginLeft: "auto", background: "transparent",
            color: fw.color, border: `1px solid ${fw.color}55`,
            borderRadius: 4, padding: "3px 9px", fontSize: 11,
            fontFamily: "ui-monospace, monospace", cursor: "pointer",
          }}>open in Frameworks →</button>
      </div>

      <div style={{ fontSize: 12.5, color: C.textDim, marginBottom: 14, lineHeight: 1.6 }}>{fw.desc}</div>

      {memberClusters.length > 0 && (
        <div style={{ marginBottom: 12, display: "flex", gap: 6, flexWrap: "wrap", alignItems: "center" }}>
          <span style={{ fontSize: 10, color: C.muted, fontFamily: "ui-monospace, monospace", letterSpacing: 0.4 }}>CLUSTERS</span>
          {memberClusters.map(cl => (
            <span key={cl.name} style={{
              fontSize: 10.5, color: cl.color,
              background: `${cl.color}14`, border: `1px solid ${cl.color}33`,
              padding: "2px 8px", borderRadius: 10,
              fontFamily: "ui-monospace, monospace",
            }}>{cl.name}</span>
          ))}
        </div>
      )}

      {relations.length === 0 ? (
        <div style={{ fontSize: 12, color: C.muted, fontStyle: "italic" }}>
          No relations of the currently-enabled types. Toggle more edge types above.
        </div>
      ) : (
        Object.entries(byType).map(([type, rs]) => {
          const ec = EDGE_TYPES[type];
          return (
            <div key={type} style={{ marginBottom: 14 }}>
              <div style={{
                fontSize: 10.5, color: ec.color, fontFamily: "ui-monospace, monospace",
                letterSpacing: 0.6, fontWeight: 700, marginBottom: 8,
                display: "flex", alignItems: "center", gap: 8,
              }}>
                <EdgeGlyph ec={ec} />
                {ec.label.toUpperCase()} · {rs.length}
              </div>
              {rs.map((r, i) => {
                const otherFw = FRAMEWORKS[r.otherKey];
                if (!otherFw) return null;
                const arrow = ec.arrow
                  ? (r.direction === "outgoing" ? "→" : "←")
                  : "↔";
                return (
                  <div key={i} style={{
                    fontSize: 12.5, color: C.text, lineHeight: 1.6,
                    paddingLeft: 14, position: "relative",
                    marginBottom: i < rs.length - 1 ? 14 : 0,
                    borderLeft: `2px solid ${ec.color}33`,
                    paddingTop: 2, paddingBottom: 2,
                  }}>
                    <div style={{ marginBottom: r.detail ? 6 : 0 }}>
                      <span style={{
                        fontFamily: "ui-monospace, monospace", color: otherFw.color,
                        fontWeight: 600, marginRight: 4,
                      }}>{arrow} {otherFw.short}</span>
                      <span style={{ color: C.muted, fontSize: 11.5 }}>
                        ({otherFw.label})
                      </span>
                      <span style={{ color: C.muted }}> · </span>
                      <span style={{ fontWeight: 500 }}>{r.note}</span>
                    </div>
                    {r.detail && (
                      <div style={{
                        fontSize: 12, color: C.textDim, lineHeight: 1.65,
                        paddingLeft: 8, paddingRight: 2,
                        borderLeft: `1px dotted ${C.border}`,
                        marginTop: 4,
                      }}>
                        {r.detail}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          );
        })
      )}
    </div>
  );
}

function GraphLegendPanel() {
  return (
    <div style={{
      background: C.surface, border: `1px solid ${C.border}`,
      borderRadius: 8, padding: "16px 20px",
    }}>
      <div style={{ fontSize: 13.5, fontWeight: 600, marginBottom: 10 }}>How to read the graph</div>
      <div style={{ fontSize: 12.5, color: C.textDim, lineHeight: 1.65, marginBottom: 14 }}>
        Frameworks are positioned in two analytical dimensions.
        <span style={{ color: C.text, fontWeight: 600 }}> Horizontal</span> — mathematical maturity: qualitative interpretive frameworks at left, rigorously formalized at right.
        <span style={{ color: C.text, fontWeight: 600 }}> Vertical</span> — substrate independence: how much of the framework's machinery works without committing to <em>what kind of stuff</em> the system is made of. High Y = machinery operates on abstract structure (bits, graphs, processes) indifferent to physical realization. Low Y = machinery requires specific stuff (physical fields, energy, substances with essences) and cannot be lifted without losing content.
        <br /><br />
        <span style={{ color: C.text, fontWeight: 600 }}>Shape encodes category</span>: hexagon = anchor, circle = productive framework, rounded square = metaphysical system.
        Node size reflects how many concepts in the atlas use that framework.
        <br /><br />
        <span style={{ color: C.muted, fontStyle: "italic" }}>Note: substrate independence ≠ scope. Substance metaphysics has wide scope (you can apply substance-talk to anything) but is deeply substrate-committed (its machinery REQUIRES substantial bearers with essences). Process philosophy explicitly REJECTS substrate priority — so it scores high.</span>
        <br /><br />
        <span style={{ color: C.text }}>Hover any node for a preview. Click a node to pin it</span> — the detail panel then stays in place as you scroll. Click empty space (or the × on the pin indicator) to unpin.
      </div>
      <div style={{ marginTop: 14 }}>
        <div style={{
          fontSize: 10, color: C.muted, fontFamily: "ui-monospace, monospace",
          letterSpacing: 0.7, fontWeight: 700, marginBottom: 10,
        }}>SHAPES — category</div>
        <div style={{ display: "flex", gap: 16, flexWrap: "wrap", alignItems: "center", marginBottom: 12 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <svg width="28" height="28" viewBox="0 0 28 28">
              <polygon points={hexPoints(14, 14, 11)} fill={`${C.sr}22`} stroke={C.sr} strokeWidth="1.5" />
            </svg>
            <span style={{ fontSize: 11.5, color: C.textDim }}>Anchor</span>
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <svg width="28" height="28" viewBox="0 0 28 28">
              <circle cx="14" cy="14" r="10" fill={`${C.pc}22`} stroke={C.pc} strokeWidth="1.5" />
            </svg>
            <span style={{ fontSize: 11.5, color: C.textDim }}>Productive framework</span>
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <svg width="28" height="28" viewBox="0 0 28 28">
              <rect x="4" y="4" width="20" height="20" rx="4" fill={`${C.pro}22`} stroke={C.pro} strokeWidth="1.5" />
            </svg>
            <span style={{ fontSize: 11.5, color: C.textDim }}>Metaphysical system</span>
          </div>
        </div>
      </div>
      <div style={{ marginTop: 14 }}>
        <div style={{
          fontSize: 10, color: C.muted, fontFamily: "ui-monospace, monospace",
          letterSpacing: 0.7, fontWeight: 700, marginBottom: 10,
        }}>EDGE TYPES — each has a distinct visual signature</div>
        {Object.entries(EDGE_TYPES).map(([type, ec]) => (
          <div key={type} style={{
            display: "flex", alignItems: "center", gap: 14,
            paddingBottom: 7, marginBottom: 7,
            borderBottom: `1px solid ${C.border}`,
          }}>
            <div style={{ width: 48, display: "flex", alignItems: "center", justifyContent: "center" }}>
              <EdgeGlyph ec={ec} />
            </div>
            <div style={{
              fontSize: 10.5, color: ec.color, fontFamily: "ui-monospace, monospace",
              letterSpacing: 0.5, fontWeight: 700,
              background: `${ec.color}14`, border: `1px solid ${ec.color}33`,
              padding: "1px 7px", borderRadius: 3, minWidth: 78, textAlign: "center",
            }}>{ec.label}</div>
            <div style={{ fontSize: 11.5, color: C.textDim, lineHeight: 1.5 }}>
              {ec.desc}
              {ec.arrow && <span style={{ color: C.muted }}> · directed</span>}
            </div>
          </div>
        ))}
      </div>
      <div style={{ marginTop: 18 }}>
        <div style={{
          fontSize: 10, color: C.muted, fontFamily: "ui-monospace, monospace",
          letterSpacing: 0.7, fontWeight: 700, marginBottom: 10,
        }}>CLUSTERS — natural groupings beyond the category split</div>
        {FW_CLUSTERS.map(cl => (
          <div key={cl.name} style={{
            display: "flex", alignItems: "baseline", gap: 12,
            paddingBottom: 6, marginBottom: 6,
            borderBottom: `1px solid ${C.border}`,
          }}>
            <div style={{
              fontSize: 10.5, color: cl.color,
              background: `${cl.color}14`, border: `1px dashed ${cl.color}66`,
              padding: "1px 8px", borderRadius: 10,
              fontFamily: "ui-monospace, monospace", whiteSpace: "nowrap",
            }}>{cl.name}</div>
            <div style={{ fontSize: 11.5, color: C.textDim, lineHeight: 1.5 }}>
              {cl.note}
              <span style={{ color: C.muted, marginLeft: 6 }}>
                ({cl.members.map(m => FRAMEWORKS[m]?.short).join(", ")})
              </span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ─── SHARED COMPONENTS ───────────────────────────────────────────────────────
function FrameworkBlock({ label, short, color, bg, border, content, symbols, isAnchor }) {
  if (!content) return null;
  return (
    <div style={{
      marginBottom: 14, padding: "12px 14px",
      background: bg || "transparent",
      border: `1px solid ${border || C.border}`,
      borderLeft: `3px solid ${color}`, borderRadius: 5,
    }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 8 }}>
        <div style={{
          fontSize: 10, color: color, fontFamily: "ui-monospace, monospace",
          letterSpacing: 0.5, fontWeight: 700,
          background: `${color}14`, border: `1px solid ${color}33`,
          padding: "1px 6px", borderRadius: 3,
        }}>{short}</div>
        <div style={{ fontSize: 13, fontWeight: 600, color: C.text }}>{label}</div>
        {isAnchor && (
          <div style={{
            fontSize: 9, color: C.muted, fontFamily: "ui-monospace, monospace",
            letterSpacing: 0.5, marginLeft: "auto",
          }}>ANCHOR</div>
        )}
      </div>
      <div style={{ fontSize: 12.5, color: C.text, lineHeight: 1.6 }}>{content}</div>
      {symbols && (
        <div style={{
          marginTop: 8, padding: "8px 10px",
          background: C.surface2, border: `1px solid ${C.border}`,
          borderRadius: 4, fontSize: 12, color: C.textDim,
          fontFamily: "ui-monospace, 'IBM Plex Mono', monospace",
          whiteSpace: "pre-wrap", overflow: "auto", lineHeight: 1.7,
        }}>
          {symbols.split("\n").map((line, i) => (
            <div key={i}>{renderFormula(line) || "\u00A0"}</div>
          ))}
        </div>
      )}
    </div>
  );
}
