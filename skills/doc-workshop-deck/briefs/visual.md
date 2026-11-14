# Brief — the visual reviewer (doc-workshop-deck)

**Inputs:** the rendered slide images `{image_paths}`. Open and look at every one.
The deck will be projected in a meeting room and read from about six metres away.

**Done looks like:** every visible defect, each with its slide number and the exact element:

- text overflowing or cut off at a box or slide edge (check this first);
- overlapping elements, an arrow through a word, a footer hitting content;
- low contrast (light on light, dark on dark), including icons;
- text too small to read from the back row;
- a diagram whose arrows or labels did not render, or that does not show what the headline
  claims;
- the same kind of slide with its headline in a different place.

**Constraints:** read-only, change nothing. Report only what you saw in an image, never what
the code implies. "No defects" is a valid answer.

**Reply with only JSON:** `[{"slide","element","defect","severity":"high|low"}]`
