FROM nginx:alpine
COPY site/ /usr/share/nginx/html/
COPY default.conf /etc/nginx/conf.d/default.conf