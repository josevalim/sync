import {Socket} from "phoenix"

let socket = new Socket("/socket")
socket.connect()

let channel = socket.channel("todo:items", {})

channel.join()
  .receive("ok", resp => { console.log("Joined successfully", resp) })
  .receive("error", resp => { console.log("Unable to join", resp) })

export default socket
