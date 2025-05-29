def get_hash(plan, image):
    result = plan.run_sh(
        name="agglayer-vkey-hash-getter",
        description="Getting agglayer vkey hash",
        image=image,
        run="agglayer vkey | tr -d '\n'",
    )
    return result.output


def get_selector(plan, image):
    # Get agglayer image tag from the format "ghcr.io/agglayer/agglayer:<tag>"
    split = image.split(":")
    if len(split) != 2:
        fail("Invalid agglayer image format: " + image)
    tag = split[1]

    # Check if the image supports "agglayer vkey-selector" command.
    if tag.startswith("0.1") or tag.startswith("0.2"):
        # For versions 0.1.x and 0.2.x, we return a fixed selector.
        return "0x00000001"

    # For versions 0.3.x and later, we run the command to get the selector.
    result = plan.run_sh(
        name="agglayer-vkey-selector-getter",
        description="Getting agglayer vkey selector",
        image=image,
        run="agglayer vkey-selector | tr -d '\n'",
    )
    return result.output
