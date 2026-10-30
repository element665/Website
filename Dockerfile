# Stage 1: shrink oversized photos. Originals stay untouched in git; only the copy baked into
# the image is downsized. This stage only copies the images, so editing HTML/CSS/nginx config
# does not re-run it (it stays cached until a photo changes).
FROM alpine:3 AS images
RUN apk add --no-cache python3 py3-pillow
COPY scripts/optimize_images.py /opt/optimize_images.py
COPY site/assets/images/ /out/
RUN python3 /opt/optimize_images.py /out

# Stage 2: assemble the site with the optimized images swapped in. Done in a separate stage so the
# original photos never end up in a layer of the final image (layers only ever add data).
FROM alpine:3 AS assemble
COPY site/ /out/
RUN rm -rf /out/assets/images && find /out -name .DS_Store -delete
COPY --from=images /out/ /out/assets/images/

# Stage 3: the image that actually ships.
FROM nginx:alpine
COPY --from=assemble /out/ /usr/share/nginx/html/
COPY default.conf /etc/nginx/conf.d/default.conf
