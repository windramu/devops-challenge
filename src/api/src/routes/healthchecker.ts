// src/routes/health.ts
import { Request, Response, Router } from "express";

const healthRouter = Router();

healthRouter.get("/", (req: Request, res: Response) => {
    // Perform any checks here, e.g., database connection
    const healthStatus = {
        status: "UP",
        timestamp: new Date().toISOString(),
        // Add other checks here if needed
    };
    res.status(200).json(healthStatus);
});

export default healthRouter;