//
//  ConversationView.swift
//  Mantras
//
//  Created by Peter Sugihara on 7/31/23.
//

import SwiftUI
import MarkdownUI

struct ConversationView: View {
  enum Position {
    case bottom
  }
  
  @Environment(\.managedObjectContext) private var viewContext
  
  @ObservedObject var conversation: Conversation
  
  @ObservedObject var agent: Agent
  @State var pendingMessage: Message?
  
  var messages: [Message] {
    conversation.orderedMessages
  }
  
  @State var pendingMessageOpacity = 0.0
  
  var body: some View {
    ScrollView {
      ScrollViewReader { proxy in
        VStack(alignment: .leading) {
          ForEach(messages) { m in
            if m == messages.last {
              if m == pendingMessage {
                MessageView(pendingMessage!, overrideText: agent.pendingMessage, agentStatus: agent.status)
                  .id(Position.bottom)
                  .opacity(pendingMessageOpacity)
                  .offset(x: -20 * (1 - pendingMessageOpacity))
                  .animation(Animation.easeOut(duration: 0.6).delay(0.6), value: pendingMessageOpacity)
              } else {
                MessageView(m, agentStatus: nil).id(Position.bottom)
              }
            } else {
              MessageView(m, agentStatus: nil).transition(.opacity)
            }
          }
        }
        .padding(.vertical, 12)
        .onReceive(
          agent.$pendingMessage.debounce(for: .seconds(1), scheduler: RunLoop.main)
        ) { _ in
          let fiveSecondsAgo = Date() - TimeInterval(5) // 5 seconds ago
          let last = messages.last
          if last?.createdAt != nil, last!.createdAt! >= fiveSecondsAgo, last!.text != nil, last!.text! != "" {
            proxy.scrollTo(Position.bottom, anchor: .top)
          }
        }
      }
    }
    .textSelection(.enabled)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      MessageTextField(conversation: conversation, onSubmit: { s in
        submit(s)
      })
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      Task {
        if agent.status == .cold, agent.prompt != conversation.prompt {
          agent.prompt = conversation.prompt ?? ""
          await agent.warmup()
        }
      }
    }
    .onChange(of: conversation) { nextConvo in
      Task {
        if agent.status == .cold, agent.prompt != conversation.prompt {
          agent.prompt = nextConvo.prompt ?? ""
          await agent.warmup()
        }
      }
    }
  }
  
  @MainActor
  func submit(_ input: String) {
    if (agent.status == .processing || agent.status == .coldProcessing) {
      Task {
        await agent.interrupt()
        submit(input)
      }
      return
    }
    
    // Create user's message
    _ = try! Message.create(text: input, fromId: Message.USER_SPEAKER_ID, conversation: conversation, inContext: viewContext)
    pendingMessageOpacity = 0

    // Pending message for bot's reply
    let m = Message(context: viewContext)
    m.fromId = agent.id
    m.createdAt = Date()
    m.text = ""
    m.conversation = conversation
    pendingMessage = m
    agent.prompt = conversation.prompt ?? agent.prompt
    withAnimation {
      pendingMessageOpacity = 1
    }
    let currentConvo = conversation
    
    Task {
      let response = await agent.listenThinkRespond(speakerId: Message.USER_SPEAKER_ID, message: input)
      
      DispatchQueue.main.async {
        currentConvo.prompt = agent.prompt
        m.text = response.text
        m.predictedPerSecond = response.predictedPerSecond ?? -1
        m.responseStartSeconds = response.responseStartSeconds ?? -1
        m.modelName = response.modelName
        if m.text == "" {
          viewContext.delete(m)
        }
        do {
          try viewContext.save()
        } catch (let error) {
          print("error creating message", error.localizedDescription)
        }
        withAnimation {
          pendingMessage = nil
          agent.pendingMessage = ""
        }

      }
    }
  }
  
}

//struct ConversationView_Previews: PreviewProvider {
//  static var previews: some View {
//    let ctx = PersistenceController.preview.container.viewContext
//    let c = try! Conversation.create(ctx: ctx)
//    let _ = try! Message.create(text: "hello", conversation: c, inContext: ctx)
//    let _ = try! Message.create(text: "Hi", conversation: c, inContext: ctx)
//
//
//    ConversationView(conversation: c).environment(\.managedObjectContext, ctx)
//  }
//}

