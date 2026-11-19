FROM node:26-alpine3.24

#create app directory
WORKDIR /app

# install dependencies 
# A Wildcard to make sure that we will copy both package.json and package-lock.json
COPY package*.json /app/

RUN npm install

# Bundle app source
COPY . . 

# Application version shown on the home page.
# Set at build time: docker build --build-arg APP_VERSION=2 ...  (default: 0)
ARG APP_VERSION=0
ENV APP_VERSION=$APP_VERSION

USER node

EXPOSE 8080
CMD ["npm", "start"]