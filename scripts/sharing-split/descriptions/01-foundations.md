

# My [no LLM editor] Description

## Intro
So I'm going to review each line in these PRs, then write in my own words what is going on in an attempt to put a more human voice on this design. Going to try to keep them short and to the point, with the exception of this PR because I need to provide a little context to get people going on this train of thought.

The core conceit here is that for a subset of existing game behavior, we own execution _end to end_. This is me applying my bag of tricks from doing this type of refactor to this type of system countless times. It is largely a UI problem to me, and my usual way to approach that category of problem borrows heavilly from reactive programming. This PR uses the combination of a service layer in the form of the `unit_transfer_controller` and `resource_transfer_controller` and then below that a policy pattern or game behavior in order to encapsulate state and categorize commonality between behaviors in our types at various points in our functional execution layer.

## PolicyType

The first real thing to understand is the `PolicyType` enum, which represents every type of behavior our modules can express:
* metal_transfer
* energy_transfer
* unit_transfer

Note that this enum could easilly map ALL behavioral categories as part of a more opinionated framework. As we expanded this pattern to other behaviors, this list would grow with the number of behavioral subsystems we refactored into. Therefore, it is important to remember that a lot of the boilerplate orchestrator functions here are truly framework code, even if they're probably not in their final form or directory. They're still a pure function that represents the same exact parameters they will ultimately have under a more opinionated framework. And they are subsequently highly portable.

### How does it fit together?

So we have PolicyType, but what are the other pieces of a unified game side execution in these categories?

Basically, it's:

```mermaid
flowchart TD
    Engine[Engine]

    subgraph Synced
        subgraph SL["Internal Service Layer"]
            direction TB
            Controller["behavior_controller<br/>(game_unit_transfer_controller, …)"]
            Context["Context<br/>(cached)"]
            Policy[Policy]
            Result[PolicyResult]
            Controller --> Context --> Policy --> Result
        end
        Gadgets["External gadgets"]
    end

    subgraph Unsynced
        UI[UI]
    end

    Commands["«commands»<br/>GG.* action API<br/>executed within bounds set by PolicyResult"]
    classDef iface stroke-dasharray:6 4,fill:#ffffff;
    class Commands iface

    Engine --> Controller
    Result -->|published cache| Gadgets
    Result -->|published cache| UI
    Gadgets -.->|execute| Commands
    UI -.->|execute| Commands
    Commands -.->|mutates| Controller
```

Let's talk through each piece of that architecture in order.

### PolicyResult

These are the central goal: establish a ["view model"](https://en.wikipedia.org/wiki/View_model) simplifying the game behavior matrix for downstream consumers. This construct is that view model. We're skipping a few steps here but don't worry we'll come back to those other execution steps in a second. 

Let's start with an example, the `UnitPolicyResult`:

```lua
---@class PolicyResult
---@field senderTeamId number
---@field receiverTeamId number

-- Unit Transfer Action
---@class UnitPolicyResult : PolicyResult
---@field canShare boolean
---@field sharingModes string[]
---@field stunSeconds number
---@field stunCategory string
---@field techBlocking? TechBlockingContext
```

This is our authoritative matrix of game behaviors as it pertains to the `PolicyType`=`unit_transfer` and the type itself existing is inherently simplifying. It is portable across layers in a way that unifies code that deals with that behavior category. Every downstream system just has to consume this type in order to understand every permutation of behavior possible. Each key is orthogonal behavior by design.

Seeing PolicyType and a functional file scoped to a particular one is self-descriptive. We get a way to speak about game behavior at runtime with type enforcement -- in a way that current patterns have major downsides described in the Architecture document [here](https://github.com/beyond-all-reason/RecoilEngine/issues/2781).

### Engine -> Behavior Controller

This part is pretty easy because it's just straight up service layer encapsulating state from an external API. It is the master of its own internal state and all downstream consumers talk to this layer, so it can be confident in its factoring that it is just ensuring its own internal state gets updated correctly and it responds to all engine requests faithful to the wishes expressed by that internal state engine.

### Context (cached inputs)

So `PolicyResult` can only exist with boilerplate that enables them to have their inputs disconnected from the engine. You need a type to express your explicit inputs from the engine to allow hot-swappability and testability for your specific engine API surface. And you also need to build it performantly -- in Lua 5.1. That's where `ContextFactory` comes in. It's only job is to build structured, memoized state that can be cached from the engine, that the policies then use to initialize a per-team cache to drive the UI/everything else.

This is some of that "framework" code we talked about earlier. It's common to all types of game behavior and allows us to white list engine state we care about, in the shape we care about it. It is extensible from downstream consumers of a given behavioral service layer (ie game_unit_transfer_controller).

Here is an example of the from the same beahvioral vertical we have been looking at (unit_transfer) of a `PolicyContext`:

```lua
---@class PolicyContext
---@field senderTeamId number
---@field receiverTeamId number
---@field sender TeamResources
---@field receiver TeamResources
---@field springRepo SpringSynced
---@field areAlliedTeams boolean
---@field isCheatingEnabled boolean
---@field ext PolicyContextExtensions
---@field unitSharingModes? string[] Effective sharing modes (set by enricher, e.g. tech blocking)
---@field taxRate? number           Effective tax rate (set by enricher, e.g. tech blocking)
```

This gives a future developer an explicit understanding of the input data we need and cache for a given behavior expression.

### Policies

Policies produce `PolicyResult` and because we have a clearly input and output type, are extremely unit testable.

Here is the
* UnitTransferPolicy
* ResourceTransferPolicy

Notice how they are stateless, and do complicated things. But the result is extremely simple for consumers. We do as much work as we can here because it's cached. This reduces complexity for devs that just want to bring their own policy, or make simple modifications to ours. We bound the runtime cost by providing and caching the policies. We can be as expressive as we want on top of that, whether that's this implementation or something that actually builds a clean AST and is more opinionated internally.

### Downstream User Actions

This same pattern is used throughout the service layer. We establish clear inputs and outputs in the form of types for a given behavior, and then ensure our execution code conforms to the boundaries established by the `PolicyResult`.

See team_transfer/resource_transfer_synced.lua

### UI

It and supporting functions in the widget layer are all simply fluent PolicyResult enjoyers. Very simple, and very easy to rip out functional slices of behavior from things like `gui_chat` or `gui_advplayerslist` because you are just coding to the type already, anything that talks about `PolicyResult` is easy to rip out because it's inherently reactive and scoped.

## 1/7 Specific PR Analysis

So that's the meat of it. This PR specifically attempts to lay the ground work by introducing
* all of the types -- including `PolicyType` and the `PolicyResult` types pulled into this system, the various inputs and outputs, internal and external, for the synced-layer team_transfer APIs
* a textbook and generic [`NotifyIfChanged`](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8125/changes#diff-d1c826b14a7f5db762bd6a0808c2fc7c1be03ddde8532ac00d635750e3e5f790R14) provides change tracking for a given `PolicyResult`
* Comms files provide my take on a classifier using `PolicyResult` to map complicated, fractured requirements into simple functional code that is easy to reason about. 
  - Unit Transfer Comms - team_transfer/unit_transfer_comms.lua
     - DecideCommunicationCase
     - [TooltipText](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8125/changes#diff-e9ec335d9f7e11b8c525ee9b2c3717ee2d50b9c461e0d5d01265ee1ea5a8d29cR59) - one function that generates every tooltip as it pertains to unit_transfer (e.g. when you hover over the button to do that with a given selection). It provides tooltip information _relevant_ to a given unit selection and `PolicyResult`, which allows it to be VERY specific for players that might be confused about a litany of configurations the game might be in during any given moment, without letting that complexity leak into gui_advplayerlist or gui_chat.

I am SUPER proud of these implementations because they were the most difficult part of this refactor and "doing it right" if you have independently configurable mod options for a given behavior. So they got distilled down to a fine wine reduction of the problem space and I think represent a good demonstration of how much complexity you can disappear with this work.