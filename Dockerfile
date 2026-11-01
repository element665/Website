# Base images are pinned to exact versions so a build is reproducible; Dependabot opens a PR
# (which CI builds and smoke-tests) when a newer version is released.

# Stage 1: shrink oversized photos. Originals stay untouched in git; only the copy baked into
# the image is downsized. This stage only copies the images, so editing HTML/CSS/nginx config
# does not re-run it (it stays cached until a photo changes).
FROM alpine:3.24.3 AS images
RUN apk add --no-cache python3 py3-pillow
COPY scripts/optimize_images.py /opt/optimize_images.py
COPY site/assets/images/ /out/
RUN python3 /opt/optimize_images.py /out

# Stage 2: assemble the site with the optimized images swapped in, then stamp every local asset
# URL in the HTML with a content hash (styles.css?v=abc123...) so edits are never hidden by caches.
# Done in a separate stage so the original photos never end up in a layer of the final image
# (layers only ever add data).
FROM alpine:3.24.3 AS assemble
RUN apk add --no-cache python3
COPY scripts/stamp_assets.py /opt/stamp_assets.py
COPY site/ /out/
RUN rm -rf /out/assets/images && find /out -name .DS_Store -delete
COPY --from=images /out/ /out/assets/images/
RUN python3 /opt/stamp_assets.py /out

# Stage 3: the image that actually ships.
FROM nginx:1.31.8-alpine
COPY --from=assemble /out/ /usr/share/nginx/html/
COPY default.conf /etc/nginx/conf.d/default.conf
