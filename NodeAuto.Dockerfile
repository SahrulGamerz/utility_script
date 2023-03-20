FROM node:lts-alpine

RUN apk add --no-cache curl git ca-certificates && update-ca-certificates 
 	
RUN addgroup app && adduser -D -S -G app app 
	
ENV PORT=3000 
ENV RUN_SCRIPT=start 

RUN echo "#!/bin/sh" > /start.sh && echo "[ -d \"/app/.git\" ] && echo Running git pull $""GIT_URL || echo Running git clone $""GIT_URL ." >> /start.sh && echo "[ -d \"/app/.git\" ] && git pull $""GIT_URL || git clone $""GIT_URL ." >> /start.sh && echo "echo Running npm install" >> /start.sh && echo "npm install" >> /start.sh && echo "echo Running npm run $""RUN_SCRIPT" >> /start.sh && echo "npm run $""RUN_SCRIPT" >> /start.sh 

RUN chmod +x /start.sh && mkdir /app && chown app /app 

WORKDIR /app 
USER app

EXPOSE $PORT 

HEALTHCHECK &{["CMD-SHELL" "curl -fs http://localhost:$PORT/health || exit 1"] "5s" "3s" "0s" '\x00'} 

CMD ["/start.sh"] 