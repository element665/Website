FROM nginx:1.29
COPY site/ /usr/share/nginx/html/
CMD ["nginx", "-g", "daemon off;"]